# StockMarket ComputerBridge

Un pont entre le mod [StockMarket](https://github.com/KROIA/StockMarket) de KROIA et
[CC: Tweaked](https://github.com/cc-tweaked/CC-Tweaked) (ComputerCraft) : il expose le marché
boursier aux ordinateurs Lua, pour automatiser le trading.

- **Minecraft** 1.20.1 · **Forge** 47.x · **Java** 17
- **Dépendances** (à installer en jeu) : [StockMarket 1.3.1](https://modrinth.com/mod/kroia_stockmarket),
  [BankSystem 1.4.1](https://modrinth.com/mod/kroia_banksystem),
  [Architectury API](https://modrinth.com/mod/architectury-api),
  [ModUtilities](https://www.curseforge.com/minecraft/mc-mods/modutilities) et
  [CC: Tweaked](https://modrinth.com/mod/cc-tweaked)

## Fonctionnement

Le mod ajoute le bloc **Trading Bridge** (`stockmarketbridge:trading_bridge`, recette :
fer + redstone + papier). Posé par un joueur, il se lie automatiquement à son compte bancaire (clic droit sur le bloc : affiche le propriétaire). Connecté au
réseau d'un ordinateur (câble ou modem), il apparaît comme périphérique `trading_bridge` :
tous les ordres passés par l'ordinateur sont exécutés sur le compte du joueur lié, comme s'ils
venaient de lui.

Les ordres sont passés directement dans le moteur de matching côté serveur, sans joueur en
ligne — le bot tourne même quand vous êtes déconnecté (le serveur doit rester allumé).

> Note : les ordres du pont sont marqués comme des ordres de « bot » par StockMarket ; ils
> continuent donc d'être exécutés même quand un marché est fermé aux joueurs (maintenance).

## API Lua du périphérique

| Méthode | Retour | Description |
|---|---|---|
| `getOwner()` | `string` | Nom du joueur lié |
| `getMarkets()` | `{item, price, open}...` | Tous les marchés actifs |
| `hasMarket(item)` | `bool` | Un marché existe pour cet item |
| `getPrice(item)` | `number` | Prix actuel |
| `isMarketOpen(item)` | `bool` | Le marché est ouvert aux joueurs |
| `getPriceHistory(item, [n])` | `{time, open, high, low, close}...` | `n` dernières bougies |
| `getOrderBook(item, tiles, [min], [max])` | `{minPrice, maxPrice, tiles, volume}` | Profondeur du carnet |
| `getBalance()` | `{available, locked}` | Argent du compte lié |
| `getItemBalance(item)` | `{available, locked}` | Quantité d'items en banque |
| `buy(item, amount)` | `bool` | Ordre au marché : achat |
| `sell(item, amount)` | `bool` | Ordre au marché : vente |
| `placeLimitOrder(item, amount, price)` | `orderID` | `amount > 0` achat, `< 0` vente |
| `getOrders([item])` | `{id, item, type, amount, filled, price, status, ...}...` | Ordres du joueur lié |
| `cancelOrder(orderID)` | `bool` | Annule un ordre en attente |

Les erreurs lèvent une exception Lua (attrapable avec `pcall`).

## Exemples

Voir [`examples/`](examples) :

- `market_monitor.lua` — affiche les prix et votre solde en continu
- `auto_trader.lua` — bot simple de mean-reversion (achat/vente autour d'une moyenne mobile)

```lua
local bridge = peripheral.find("trading_bridge")
bridge.buy("minecraft:iron_ingot", 10)          -- ordre au marché
local id = bridge.placeLimitOrder("minecraft:diamond", -5, 150)  -- vente limite
print(bridge.getOrders("minecraft:diamond"))
```

## Build

Prérequis : **Java 17**.

1. Dépose les jars des mods dépendants dans [`libs/`](libs/README.md) (noms exacts indiqués dedans).
2. Génère le wrapper Gradle une seule fois (Gradle 8.x installé) : `gradle wrapper --gradle-version 8.5`
3. `./gradlew build`

Le jar est produit dans `build/libs/`. Pour tester : copie-le dans le dossier `mods/` d'une instance
Forge 1.20.1 avec StockMarket, BankSystem, ModUtilities, Architectury et CC: Tweaked.

> Les jars tiers ne sont pas dans le dépôt (`.gitignore`). Ils sont résolus via un dépôt local
> (`flatDir`) pour ne pas dépendre d'URL Maven externes.

## Sécurité

Tout ordinateur relié au pont peut dépenser **l'argent du joueur propriétaire**. Protège donc tes
ordinateurs et ton pont (claims, zone privée). `bind()` a volontairement été retiré de l'API :
il aurait permis à n'importe qui de lier un pont non posé par un joueur au compte d'un tiers.
Seuls les ordres du joueur lié peuvent être listés ou annulés via le pont.

## Textures

Recette : 4 lingots de fer, 4 papiers, 1 redstone (motif `IPI / PRP / IPI`).

Le bloc utilise la texture vanilla du bloc de fer. Pour une texture personnalisée, ajoutez
`src/main/resources/assets/stockmarketbridge/textures/block/trading_bridge.png` (16×16) et
remplacez la référence dans `models/block/trading_bridge.json`.

## Compatibilité

Développé contre les sources exactes de StockMarket `mc_1.20.1_v1.3.1` et BankSystem
`mc_1.20.1_v1.4.1` (les versions 2.x de StockMarket n'existent pas pour Forge).

## Automatisation (dossier `computer/`)

Bot de trading prêt à l'emploi pour un ordinateur CC relié au Trading Bridge.

| Fichier | Rôle |
|---|---|
| `trader.lua` | Le bot : moyenne mobile + volatilité, stop-loss, objectif de gain, arrêt d'urgence |
| `trader_config.lua` | Ta configuration (items, quantités, seuils) |
| `install.lua` | Télécharge le bot depuis GitHub sur l'ordinateur |

Installation sur l'ordinateur CC (HTTP activé) :
```
wget run https://raw.githubusercontent.com/kokogoju5-debug/pont/main/computer/install.lua startup
edit trader_config.lua
trader
```
Commandes : `trader` (lance), `trader status`, `trader reset` (efface la mémoire / relance après un arrêt d'urgence).

**`dryRun = true` par défaut** : le bot ne fait que journaliser ce qu'il ferait. Passe-le à `false`
dans `trader_config.lua` quand tu es satisfait. Un moniteur CC adjacent affiche un tableau de bord ;
le journal est dans `trader.log`.

Le coût moyen est une estimation (le pont ne renvoie pas le prix d'exécution réel).
Aucune stratégie ne garantit un gain : commence avec de petites quantités.
