local HttpService = game:GetService("HttpService")
local BASE = "https://analytics." .. "mystudio.dev"
local function track(name, props)
	HttpService:PostAsync(BASE .. "/v1/events", HttpService:JSONEncode({
		event = name, props = props,
	}))
end
return track
