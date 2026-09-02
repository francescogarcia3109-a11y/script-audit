-- Posts a moderation report to our team Discord channel.
local HttpService = game:GetService("HttpService")

local WEBHOOK = "https://discord.com/api/webhooks/1234567890123456789/" ..
	"aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"

local function report(player, reason)
	HttpService:PostAsync(WEBHOOK, HttpService:JSONEncode({
		content = string.format("%s flagged: %s", player.Name, reason),
	}))
end

return report
