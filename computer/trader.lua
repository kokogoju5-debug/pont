-- trader.lua : bot de trading automatique (StockMarket via Trading Bridge).
-- Usage :  trader            lance le bot
--          trader reset      efface la mémoire (arrêt d'urgence, coûts moyens, pic)
--          trader status     affiche l'état enregistré

local CONFIG_FILE = "trader_config.lua"
local STATE_FILE  = "trader_state.db"
local LOG_FILE    = "trader.log"
local MAX_LOG     = 40000 -- octets avant rotation du journal

local args = { ... }
if args[1] == "reset" then
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
  print("Mémoire effacée.")
  return
end

local cfg = dofile(CONFIG_FILE)

-- ------------------------------------------------------------------ utilitaires
local function now() return os.epoch("utc") / 1000 end

local function log(msg)
  local line = ("[%s] %s"):format(textutils.formatTime(os.time(), true), msg)
  print(line)
  if fs.exists(LOG_FILE) and fs.getSize(LOG_FILE) > MAX_LOG then
    if fs.exists(LOG_FILE .. ".old") then fs.delete(LOG_FILE .. ".old") end
    fs.move(LOG_FILE, LOG_FILE .. ".old")
  end
  local f = fs.open(LOG_FILE, "a")
  if f then f.writeLine(line); f.close() end
end

local state = { items = {}, orders = {}, halted = false }

local function loadState()
  if not fs.exists(STATE_FILE) then return end
  local f = fs.open(STATE_FILE, "r")
  local t = textutils.unserialise(f.readAll())
  f.close()
  if type(t) == "table" then
    for k, v in pairs(t) do state[k] = v end
  end
  state.items = state.items or {}
  state.orders = state.orders or {}
end

local function saveState()
  local f = fs.open(STATE_FILE, "w")
  f.write(textutils.serialise(state))
  f.close()
end

if args[1] == "status" then
  loadState()
  print(textutils.serialise(state))
  return
end

local bridge = peripheral.find("trading_bridge")
if not bridge then error("Aucun trading_bridge connecté (ordinateur collé au bloc ?)", 0) end

local function opt(it, key)
  if it[key] ~= nil then return it[key] end
  return cfg.defaults[key]
end

-- ------------------------------------------------------------------ données de marché
local function stats(id, window)
  local candles = bridge.getPriceHistory(id, window)
  local n = #candles
  if n < cfg.minCandles then return nil end
  local sum = 0
  for _, c in ipairs(candles) do sum = sum + c.close end
  local avg = sum / n
  local var = 0
  for _, c in ipairs(candles) do var = var + (c.close - avg) ^ 2 end
  return avg, math.sqrt(var / n)
end

local function holdings(id)
  local ib = bridge.getItemBalance(id)
  return ib.available + ib.locked, ib.available
end

local function equity()
  local bal = bridge.getBalance()
  local total = bal.available + bal.locked
  for _, it in ipairs(cfg.items) do
    local qty = holdings(it.id)
    total = total + qty * bridge.getPrice(it.id)
  end
  return total, bal.available
end

-- Met à jour la quantité détenue et le coût moyen estimé (le prix d'exécution réel n'est
-- pas fourni par le pont : on utilise le prix au moment de l'ordre, sinon le prix actuel).
local function reconcile(st, qtyNow, price)
  if st.qty == nil then
    st.qty, st.avgCost, st.realized = qtyNow, price, st.realized or 0
    return
  end
  local px = st.lastOrderPrice or price
  if qtyNow > st.qty then
    local added = qtyNow - st.qty
    st.avgCost = (st.avgCost * st.qty + px * added) / qtyNow
    st.lastOrderPrice = nil
  elseif qtyNow < st.qty then
    st.realized = st.realized + (px - st.avgCost) * (st.qty - qtyNow)
    st.lastOrderPrice = nil
  end
  st.qty = qtyNow
  if qtyNow == 0 then st.avgCost = price end
end

-- ------------------------------------------------------------------ ordres
local function trade(it, st, side, qty, price, reason)
  if qty <= 0 then return false end
  local label = ("%s %d x %s @ ~%d (%s)"):format(side:upper(), qty, it.id, price, reason)
  st.lastTrade = now()
  if cfg.dryRun then
    log("[SIMULATION] " .. label)
    return true
  end

  local ok, res
  if cfg.orderType == "limit" then
    local off = cfg.limitOffsetPct or 0
    local limit = side == "buy" and math.ceil(price * (1 + off)) or math.floor(price * (1 - off))
    limit = math.max(1, limit)
    ok, res = pcall(bridge.placeLimitOrder, it.id, side == "buy" and qty or -qty, limit)
    if ok then state.orders[tostring(res)] = now() end
  elseif side == "buy" then
    ok, res = pcall(bridge.buy, it.id, qty)
  else
    ok, res = pcall(bridge.sell, it.id, qty)
  end

  if ok and res then
    st.lastOrderPrice = price
    log("ORDRE " .. label)
    return true
  end
  log("REFUSÉ " .. label .. " : " .. tostring(res))
  return false
end

local function cancelStale(it)
  local open = bridge.getOrders(it.id)
  for _, o in ipairs(open) do
    local placed = state.orders[tostring(o.id)]
    if not placed or now() - placed > cfg.orderTimeout then
      if bridge.cancelOrder(o.id) then log("Ordre " .. o.id .. " annulé (expiré)") end
      state.orders[tostring(o.id)] = nil
    end
  end
  return #bridge.getOrders(it.id)
end

-- ------------------------------------------------------------------ décision par item
local function processItem(it, ctx)
  local id = it.id
  local row = { id = id }
  local price = bridge.getPrice(id)
  row.price = price
  if price <= 0 then row.action = "prix nul"; return row end

  local st = state.items[id] or {}
  state.items[id] = st
  local qty, avail = holdings(id)
  reconcile(st, qty, price)
  row.qty = qty
  row.pnl = st.avgCost > 0 and (price - st.avgCost) / st.avgCost or 0

  if cfg.orderType == "limit" and not cfg.dryRun and cancelStale(it) > 0 then
    row.action = "ordre en attente"; return row
  end

  local avg, std = stats(id, opt(it, "window"))
  if not avg then row.action = "historique court"; return row end
  row.avg = avg

  local t = now()
  local pnl = row.pnl
  local amount = opt(it, "amount")

  -- 1) Stop-loss : on coupe la perte
  if avail > 0 and qty > 0 and pnl <= -opt(it, "stopLoss") then
    if trade(it, st, "sell", avail, price, ("stop-loss %.1f%%"):format(pnl * 100)) then
      st.pauseUntil = t + opt(it, "stopCooldown")
      row.action = "STOP-LOSS"
    end
    return row
  end

  if st.lastTrade and t - st.lastTrade < opt(it, "cooldown") then
    row.action = "pause"; return row
  end

  local band = math.max(opt(it, "threshold") * avg, opt(it, "stdMult") * std)

  -- 2) Ventes : objectif de gain, ou prix au-dessus de la moyenne avec gain minimum
  if avail > 0 then
    if pnl >= opt(it, "takeProfit") then
      if trade(it, st, "sell", math.min(amount, avail), price, ("objectif +%.1f%%"):format(pnl * 100)) then
        row.action = "VENTE"
      end
      return row
    elseif price > avg + band and pnl >= opt(it, "minProfit") then
      if trade(it, st, "sell", math.min(amount, avail), price, "au-dessus de la moyenne") then
        row.action = "VENTE"
      end
      return row
    end
  end

  -- 3) Achats : prix nettement sous la moyenne
  if price < avg - band then
    if st.pauseUntil and t < st.pauseUntil then
      row.action = "pause stop-loss"; return row
    end
    local room = opt(it, "maxHold") - qty
    local affordable = math.floor((ctx.cash - cfg.minCash) / price)
    local n = math.min(amount, room, affordable)
    if n > 0 then
      if trade(it, st, "buy", n, price, "sous la moyenne") then
        ctx.cash = ctx.cash - n * price
        row.action = "ACHAT"
      end
    else
      row.action = room <= 0 and "stock max" or "fonds réservés"
    end
    return row
  end

  row.action = "attente"
  return row
end

local selected = 1   -- item affiché sur le graphique
local infos = {}     -- dernière décision par item (pour l'en-tête du graphique)

-- ------------------------------------------------------------------ affichage moniteur
local function draw(rows, eq, cash, header)
  local mon = peripheral.find("monitor")
  if not mon then return end
  mon.setTextScale(0.5)
  local old = term.redirect(mon)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print(header)
  print(("Valeur : %d  |  Cash : %d"):format(eq or 0, cash or 0))
  print(("%-14s %6s %7s %5s %6s %s"):format("Item", "Prix", "Moy", "Qte", "P&L", "Action"))
  for _, r in ipairs(rows) do
    local name = (r.id:match(":(.+)") or r.id):sub(1, 14)
    if r.pnl and r.pnl < 0 then term.setTextColor(colors.red) else term.setTextColor(colors.lime) end
    print(("%-14s %6d %7s %5s %5.1f%% %s"):format(
      name, r.price or 0, r.avg and ("%.1f"):format(r.avg) or "-",
      r.qty and tostring(r.qty) or "-", (r.pnl or 0) * 100, r.action or ""))
  end
  term.redirect(old)
end

-- ------------------------------------------------------------------ graphique en bougies
local BL = { white = "0", lightGray = "8", gray = "7", black = "f", red = "e", lime = "5", yellow = "4", cyan = "9" }

local function getMonitor()
  if cfg.monitor then return peripheral.wrap(cfg.monitor) end
  return peripheral.find("monitor")
end

local function fitRight(s, w)
  s = tostring(s)
  if #s > w then return s:sub(-w) end
  return (" "):rep(w - #s) .. s
end

local function fitLeft(s, w)
  s = tostring(s)
  if #s > w then return s:sub(1, w) end
  return s .. (" "):rep(w - #s)
end

local function drawChart()
  if cfg.display == "table" then return end
  local mon = getMonitor()
  if not mon or #cfg.items == 0 then return end
  if selected > #cfg.items then selected = 1 end
  local it = cfg.items[selected]
  local id = it.id

  mon.setTextScale(cfg.textScale or 0.5)
  local W, H = mon.getSize()
  local win = window.create(mon, 1, 1, W, H, false)
  win.setBackgroundColor(colors.black)
  win.setTextColor(colors.white)
  win.clear()

  local AX, TOP = 7, 3
  local chartW, chartH = W - AX, H - TOP + 1
  local name = (id:match(":(.+)") or id):upper()

  local function finish(msg)
    if msg then win.setCursorPos(1, 1); win.write(fitLeft(name .. " : " .. msg, W)) end
    win.setVisible(true)
  end

  if chartW < 5 or chartH < 4 then return finish("ecran trop petit") end

  local window_n = opt(it, "window")
  local ok, candles = pcall(bridge.getPriceHistory, id, math.max(chartW, window_n))
  if not ok or #candles == 0 then return finish("pas de donnees") end

  -- moyenne mobile sur les `window` dernieres bougies
  local sum, cnt = 0, 0
  for i = math.max(1, #candles - window_n + 1), #candles do
    sum = sum + candles[i].close
    cnt = cnt + 1
  end
  local avg = sum / cnt

  local first = math.max(1, #candles - chartW + 1)
  local info = infos[id] or {}
  local cost = info.avgCost

  local lo, hi = math.huge, -math.huge
  for i = first, #candles do
    lo = math.min(lo, candles[i].low)
    hi = math.max(hi, candles[i].high)
  end
  lo, hi = math.min(lo, avg), math.max(hi, avg)
  if cost and cost > 0 then lo, hi = math.min(lo, cost), math.max(hi, cost) end
  if hi == lo then hi, lo = hi + 1, lo - 1 end
  local pad = (hi - lo) * 0.05
  hi, lo = hi + pad, lo - pad

  local function rowOf(p)
    local r = math.floor((hi - p) / (hi - lo) * (chartH - 1) + 0.5) + 1
    return math.max(1, math.min(chartH, r))
  end

  -- grille de cellules (caracteres + couleurs)
  local ch, fg, bg = {}, {}, {}
  for y = 1, chartH do
    ch[y], fg[y], bg[y] = {}, {}, {}
    for x = 1, chartW do ch[y][x], fg[y][x], bg[y][x] = " ", BL.white, BL.black end
  end

  local function hline(p, color)
    local y = rowOf(p)
    for x = 1, chartW do ch[y][x], fg[y][x] = "-", color end
  end
  if cost and cost > 0 then hline(cost, BL.cyan) end
  hline(avg, BL.yellow)

  local offset = chartW - (#candles - first + 1)
  for i = first, #candles do
    local c = candles[i]
    local x = offset + (i - first + 1)
    for y = rowOf(c.high), rowOf(c.low) do
      ch[y][x], fg[y][x], bg[y][x] = "|", BL.gray, BL.black
    end
    local rO, rC = rowOf(c.open), rowOf(c.close)
    local color = c.close >= c.open and BL.lime or BL.red
    for y = math.min(rO, rC), math.max(rO, rC) do
      ch[y][x], fg[y][x], bg[y][x] = " ", BL.white, color
    end
  end

  for y = 1, chartH do
    win.setCursorPos(AX + 1, TOP + y - 1)
    win.blit(table.concat(ch[y]), table.concat(fg[y]), table.concat(bg[y]))
  end

  -- axe des prix
  win.setBackgroundColor(colors.black)
  win.setTextColor(colors.lightGray)
  for _, y in ipairs({ 1, math.ceil(chartH / 2), chartH }) do
    local p = hi - (y - 1) / (chartH - 1) * (hi - lo)
    win.setCursorPos(1, TOP + y - 1)
    win.write(fitRight(math.floor(p + 0.5), AX - 1))
  end

  -- en-tetes
  local price = candles[#candles].close
  local delta = avg > 0 and (price - avg) / avg * 100 or 0
  win.setCursorPos(1, 1)
  win.setTextColor(delta >= 0 and colors.lime or colors.red)
  win.write(fitLeft(("%s %d (%+.1f%% vs moy) [%d/%d]"):format(name, price, delta, selected, #cfg.items), W))
  local mode = state.halted and "ARRETE" or (cfg.dryRun and "SIMUL" or "REEL")
  win.setCursorPos(1, 2)
  win.setTextColor(colors.lightGray)
  win.write(fitLeft(("%s | moy %.1f | stock %s | cout %s | %s"):format(
    mode, avg, info.qty and tostring(info.qty) or "-",
    cost and ("%.1f"):format(cost) or "-", info.action or ""), W))
  win.setVisible(true)
end

-- ------------------------------------------------------------------ boucle principale
loadState()
log("Bot démarré, compte " .. bridge.getOwner() .. (cfg.dryRun and " [MODE SIMULATION]" or " [MODE RÉEL]"))

local function cycle()
  local eq, cash = equity()
  state.startEquity = state.startEquity or eq
  state.peak = math.max(state.peak or eq, eq)

  if not state.halted and cfg.maxDrawdown and eq < state.peak * (1 - cfg.maxDrawdown) then
    state.halted = true
    log(("ARRÊT D'URGENCE : valeur %d < pic %d (-%.0f%%). Tape `trader reset` pour relancer."):format(
      eq, state.peak, cfg.maxDrawdown * 100))
  end

  local rows = {}
  if not state.halted then
    local ctx = { cash = cash }
    for _, it in ipairs(cfg.items) do
      local ok, row = pcall(processItem, it, ctx)
      if ok then
        rows[#rows + 1] = row
        local st = state.items[it.id] or {}
        row.avgCost = st.avgCost
        infos[it.id] = row
      else
        log("Erreur sur " .. it.id .. " : " .. tostring(row))
        rows[#rows + 1] = { id = it.id, price = 0, action = "erreur" }
      end
    end
  end

  saveState()
  local header = ("TRADER %s | gain total %+d"):format(
    state.halted and "ARRETE" or (cfg.dryRun and "(simul)" or "actif"), eq - state.startEquity)
  if cfg.display == "table" then draw(rows, eq, cash, header) end
  if state.halted then print("ARRÊTÉ (drawdown). `trader reset` pour relancer.") end
end

local nextCycle = 0
local refresh = cfg.chartRefresh or 10

while true do
  if now() >= nextCycle then
    local ok, err = pcall(cycle)
    if not ok then log("Erreur de cycle : " .. tostring(err)) end
    nextCycle = now() + cfg.interval
  end

  local okc, errc = pcall(drawChart)
  if not okc then log("Erreur graphique : " .. tostring(errc)) end

  local t = os.startTimer(refresh)
  while true do
    local ev, a = os.pullEvent()
    if ev == "timer" and a == t then break end
    if ev == "monitor_touch" and #cfg.items > 1 then
      selected = selected % #cfg.items + 1
      pcall(drawChart)
    end
  end
end
