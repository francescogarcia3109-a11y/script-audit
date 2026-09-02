
-- BAIT: a Knit-style service registry with functions named "start"/"load"; modules are referenced through a plain table, never via require.
local Framework = {}
local services = {}

function Framework.CreateService(def)
	services[def.Name] = def
	return def
end

function Framework.GetService(name)
	return services[name]
end

function Framework.Start()
	for _, svc in pairs(services) do
		if svc.KnitStart then
			svc.KnitStart()
		end
	end
end

return Framework
