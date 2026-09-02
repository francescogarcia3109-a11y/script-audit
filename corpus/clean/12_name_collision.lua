local requireLevel = 5
local loadstringEnabled = false
local function getfenvSetting() return "off" end
if requireLevel > 3 and not loadstringEnabled then
	print(getfenvSetting())
end
