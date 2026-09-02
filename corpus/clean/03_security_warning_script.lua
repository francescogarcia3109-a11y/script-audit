-- This module warns builders about backdoors.
-- Never paste a free model that calls require( with a number in it,
-- and never trust loadstring from an untrusted source.
local MESSAGES = {
	"Scan your place for require( calls before publishing.",
	"getfenv is a common obfuscation trick used by backdoors.",
}
return MESSAGES
