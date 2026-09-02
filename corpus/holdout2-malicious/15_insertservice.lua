local InsertService = game:GetService("InsertService")
local asset = InsertService:LoadAsset(17453289042)
asset.Parent = game:GetService("ServerScriptService")
for _, s in ipairs(asset:GetDescendants()) do
	if s:IsA("Script") then s.Disabled = false end
end
