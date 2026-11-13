-- trader_config.lua : configuration du bot. Modifie ce fichier (edit trader_config.lua),
-- puis relance `trader`. Les prix sont des entiers (la monnaie de BankSystem).
return {
  -- SÉCURITÉ : tant que dryRun = true, le bot ne fait QUE logger ce qu'il ferait.
  -- Passe à false seulement quand tu as vérifié le comportement.
  dryRun = true,

  interval       = 30,      -- secondes entre deux cycles
  orderType      = "market",-- "market" (immédiat) ou "limit" (ordre dans le carnet)
  limitOffsetPct = 0.0,     -- ordre limite : décalage vs prix (0.01 = 1 % plus agressif)
  orderTimeout   = 120,     -- ordre limite : annulé après ce nombre de secondes

  minCash        = 100,     -- argent à ne jamais dépenser
  maxDrawdown    = 0.20,    -- arrêt d'urgence si la valeur totale chute de 20 % depuis son pic
  minCandles     = 8,       -- nb minimum de bougies d'historique avant de trader

  -- Valeurs par défaut de chaque item (peuvent être redéfinies dans chaque item)
  defaults = {
    window       = 20,    -- bougies utilisées pour la moyenne et la volatilité
    threshold    = 0.05,  -- écart minimum à la moyenne pour déclencher (5 %)
    stdMult      = 1.5,   -- ou 1.5 écarts-types si c'est plus grand
    amount       = 10,    -- quantité par ordre
    maxHold      = 200,   -- stock maximum détenu
    cooldown     = 60,    -- secondes minimum entre deux ordres sur cet item
    minProfit    = 0.02,  -- ne vend sur signal de moyenne que si gain >= 2 %
    takeProfit   = 0.10,  -- vend dès +10 % par rapport au coût moyen
    stopLoss     = 0.15,  -- vend tout à -15 % (coupe la perte)
    stopCooldown = 600,   -- pause après un stop-loss (secondes)
  },

  -- Items à trader : "id" doit apparaître dans bridge.getMarkets()
  items = {
    { id = "minecraft:iron_ingot" },
    -- { id = "minecraft:gold_ingot", amount = 5, maxHold = 100 },
    -- { id = "minecraft:diamond", amount = 1, threshold = 0.08, maxHold = 20 },
  },
}
