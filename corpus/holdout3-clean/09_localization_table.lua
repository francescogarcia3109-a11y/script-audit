
-- BAIT: a localization table full of strings including the words "require" and "load"; it is pure data.
local Locale = {}

Locale.en = {
	gate_locked = "This area may require a game pass.",
	loading = "Loading your data, please wait...",
	tip_1 = "Press E near a door that requires a key.",
}

Locale.fr = {
	gate_locked = "Cette zone peut necessiter un game pass.",
	loading = "Chargement de vos donnees...",
	tip_1 = "Appuyez sur E pres d'une porte a cle.",
}

function Locale.t(lang, key)
	local tbl = Locale[lang] or Locale.en
	return tbl[key] or key
end

return Locale
