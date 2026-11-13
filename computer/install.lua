-- install.lua : télécharge le bot depuis GitHub.
--   wget run https://raw.githubusercontent.com/kokogoju5-debug/pont/main/computer/install.lua
-- Ajoute l'argument "startup" pour lancer le bot automatiquement au démarrage.
local BASE = "https://raw.githubusercontent.com/kokogoju5-debug/pont/main/computer/"
local args = { ... }

local function get(name, overwrite)
  if fs.exists(name) and not overwrite then
    print("Conservé (existe déjà) : " .. name)
    return
  end
  local r = http.get(BASE .. name)
  if not r then error("Téléchargement impossible : " .. name, 0) end
  local f = fs.open(name, "w")
  f.write(r.readAll())
  f.close()
  r.close()
  print("Installé : " .. name)
end

get("trader.lua", true)
get("trader_config.lua", false) -- ne jamais écraser ta config
if args[1] == "startup" then
  local f = fs.open("startup.lua", "w")
  f.write('shell.run("trader")\n')
  f.close()
  print("startup.lua créé : le bot se lancera au démarrage.")
end
print("Terminé. Édite trader_config.lua puis lance : trader")
