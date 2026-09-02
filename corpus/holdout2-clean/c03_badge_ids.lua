local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")

local BADGES = {
	FirstJoin = 2124586913,
	Winner = 2124586914,
	Speedrun = 2124586915,
}

local function award(player, name)
	local id = BADGES[name]
	if not id then return end
	local ok, owns = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, id)
	if ok and not owns then
		pcall(BadgeService.AwardBadge, BadgeService, player.UserId, id)
	end
end

Players.PlayerAdded:Connect(function(p)
	award(p, "FirstJoin")
end)

return award
