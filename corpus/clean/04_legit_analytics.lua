local HttpService = game:GetService("HttpService")
local ENDPOINT = "https://analytics.mystudio.example/v1/event"
local function track(name)
	HttpService:PostAsync(ENDPOINT, HttpService:JSONEncode({ event = name }))
end
return track
