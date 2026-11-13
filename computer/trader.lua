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
      else
        log("Erreur sur " .. it.id .. " : " .. tostring(row))
        rows[#rows + 1] = { id = it.id, price = 0, action = "erreur" }
      end
    end
  end

  saveState()
  local header = ("TRADER %s | gain total %+d"):format(
    state.halted and "ARRÊTÉ" or (cfg.dryRun and "(simul)" or "actif"), eq - state.startEquity)
  draw(rows, eq, cash, header)
  if state.halted then print("ARRÊTÉ (drawdown). `trader reset` pour relancer.") end
end

while true do
  local ok, err = pcall(cycle)
  if not ok then log("Erreur de cycle : " .. tostring(err)) end
  sleep(cfg.interval)
end
