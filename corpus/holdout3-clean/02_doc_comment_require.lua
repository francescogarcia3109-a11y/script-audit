
-- BAIT: the words "require" and "loadstring" appear only in comments and player-facing strings; no dynamic loading happens.
local Help = {}

-- NOTE: builds using loadstring are banned on this place; do not require untrusted assets.
Help.topics = {
	building = "You do not need to require any pass to build here.",
	scripting = "loadstring is disabled; use ModuleScripts placed by the dev team.",
}

function Help.get(topic)
	return Help.topics[topic] or "No help available."
end

return Help
