-- auto_trader.lua : bot de "mean reversion" très simple.
--   * prix < moyenne mobile * (1 - SEUIL)  -> achète
--   * prix > moyenne mobile * (1 + SEUIL)  -> vend
-- ATTENTION : exemple pédagogique, pas un conseil de trading. Commence avec de petites quantités.

local CONFIG = {
  item       = "minecraft:iron_ingot", -- item à trader (doit avoir un marché)
  window     = 20,    -- nombre de bougies pour la moyenne mobile
  threshold  = 0.05,  -- écart de 5 % déclenchant un ordre
  amount     = 10,    -- quantité par ordre
  maxHold    = 200,   -- ne jamais détenir plus que ça
  minCash    = 100,   -- garde au moins cette somme en banque
  interval   = 30,    -- secondes entre deux décisions
}

local bridge = peripheral.find("trading_bridge")
if not bridge then error("Aucun trading_bridge connecté", 0) end
if not bridge.hasMarket(CONFIG.item) then error("Pas de marché pour " .. CONFIG.item, 0) end

local function movingAverage()
  local candles = bridge.getPriceHistory(CONFIG.item, CONFIG.window)
  if #candles == 0 then return nil end
  local sum = 0
  for _, c in ipairs(candles) do sum = sum + c.close end
  return sum / #candles
end

local function log(msg)
  print(("[%s] %s"):format(textutils.formatTime(os.time(), true), msg))
end

log("Bot démarré sur " .. CONFIG.item .. " (compte " .. bridge.getOwner() .. ")")

while true do
  local ok, err = pcall(function()
    local price = bridge.getPrice(CONFIG.item)
    local avg = movingAverage()
    if not avg or avg <= 0 or price <= 0 then
      log("Pas assez de données, j'attends...")
      return
    end

    local cash  = bridge.getBalance().available
    local items = bridge.getItemBalance(CONFIG.item).available
    log(("prix=%d  moyenne=%.1f  cash=%d  stock=%d"):format(price, avg, cash, items))

    if price < avg * (1 - CONFIG.threshold) then
      local qty = math.min(CONFIG.amount, CONFIG.maxHold - items)
      local cost = qty * price
      if qty > 0 and cash - cost >= CONFIG.minCash then
        log(("ACHAT %d x %s (~%d)"):format(qty, CONFIG.item, cost))
        if not bridge.buy(CONFIG.item, qty) then log("  achat refusé") end
      end
    elseif price > avg * (1 + CONFIG.threshold) then
      local qty = math.min(CONFIG.amount, items)
      if qty > 0 then
        log(("VENTE %d x %s"):format(qty, CONFIG.item))
        if not bridge.sell(CONFIG.item, qty) then log("  vente refusée") end
      end
    end
  end)
  if not ok then log("Erreur : " .. tostring(err)) end
  sleep(CONFIG.interval)
end
