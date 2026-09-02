-- A dispatcher whose action names happen to include "require"
local action = "require"
local Router = {}
Router.action = function(payload) return payload end
print(Router.action({ kind = action }))
