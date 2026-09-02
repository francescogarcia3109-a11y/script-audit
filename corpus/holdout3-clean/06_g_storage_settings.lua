
-- BAIT: _G and shared used as ordinary cross-script settings storage; no loader is fetched from them.
_G.GameConfig = _G.GameConfig or {
	roundTime = 120,
	maxPlayers = 12,
	mapPool = { "Desert", "Snow", "City" },
}

shared.Scores = shared.Scores or {}

local Config = {}

function Config.get(key)
	return _G.GameConfig[key]
end

function Config.setScore(player, value)
	shared.Scores[player.UserId] = value
end

return Config
