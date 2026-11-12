# libs/

Dépose ici les jars **Forge 1.20.1** des mods dont dépend le pont, renommés exactement ainsi
(les versions se règlent dans `gradle.properties`) :

| Fichier à créer | Mod | Version |
|---|---|---|
| `stockmarket-1.3.1.jar` | StockMarket (KROIA) | 1.3.1 |
| `banksystem-1.4.1.jar` | BankSystem (KROIA) | 1.4.1 |
| `modutilities-1.2.0.jar` | ModUtilities (KROIA) | 1.2.0 |
| `architectury-9.2.14.jar` | Architectury API (Forge) | 9.2.14 |
| `cc-tweaked-1.115.1.jar` | CC: Tweaked (Forge 1.20.1) | 1.115.1 |

Si tu utilises une autre version de CC: Tweaked, change `cctweaked_version` dans
`gradle.properties` et renomme le jar en conséquence.

Les jars ne sont pas versionnés dans Git (`.gitignore`).
