local HttpService = game:GetService("HttpService")

local WEBHOOK = "https://discord.com/api/webhooks/"
	.. "1234567890123456789/"
	.. "abcdefghijklmnopqrstuvwxyz"

local function report(title, text)
	local body = HttpService:JSONEncode({
		embeds = { { title = title, description = text } },
	})
	local ok, err = pcall(function()
		HttpService:PostAsync(WEBHOOK, body)
	end)
	if not ok then
		warn("webhook failed: " .. tostring(err))
	end
end

return report
