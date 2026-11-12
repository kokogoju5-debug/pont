# libs/

Jars **Forge 1.20.1** nécessaires pour compiler le pont. Noms attendus (les versions se règlent
dans `gradle.properties`) :

| Fichier | Mod |
|---|---|
| `stockmarket-forge-1.3.1.jar` | StockMarket (KROIA) |
| `banksystem-forge-1.4.1.jar` | BankSystem (KROIA) |
| `modutilities-forge-1.2.0.jar` | ModUtilities (KROIA) |
| `architectury-9.2.14-forge.jar` | Architectury API |
| `cc-tweaked-1.20.1-forge-1.115.1.jar` | CC: Tweaked |

`modutilities-forge-1.2.0.jar` n'est pas installé séparément en jeu : il est embarqué dans le jar
de BankSystem (`META-INF/jars/`). Pour l'obtenir, ouvre `banksystem-forge-1.4.1.jar` comme un zip
et extrais-le de là.

Ces jars appartiennent à leurs auteurs : ne les redistribue pas dans un dépôt public.
