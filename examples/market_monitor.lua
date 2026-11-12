-- market_monitor.lua : affiche les prix de tous les marchés et ton solde en continu.
-- Usage : branche l'ordinateur (câble/modem) au Trading Bridge, puis `market_monitor`.

local bridge = peripheral.find("trading_bridge")
if not bridge then error("Aucun trading_bridge connecté", 0) end

local REFRESH = 5 -- secondes

while true do
  term.clear()
  term.setCursorPos(1, 1)
  print("== Marché  (compte : " .. bridge.getOwner() .. ") ==")

  local ok, bal = pcall(bridge.getBalance)
  if ok then
    print(("Solde : %d (bloqué : %d)"):format(bal.available, bal.locked))
  else
    print("Solde : erreur - " .. tostring(bal))
  end
  print()

  local markets = bridge.getMarkets()
  table.sort(markets, function(a, b) return a.item < b.item end)
  for _, m in ipairs(markets) do
    print(("%-32s %8d %s"):format(m.item, m.price, m.open and "" or "[fermé]"))
  end

  sleep(REFRESH)
end
