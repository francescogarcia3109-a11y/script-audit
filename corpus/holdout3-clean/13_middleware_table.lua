
-- BAIT: a table-of-functions request pipeline (looks like function-table indirection) where every stage is a benign local transform.
local Pipeline = {}

local stages = {
	function(ctx) ctx.trimmed = string.gsub(ctx.raw, "^%s+", ""); return ctx end,
	function(ctx) ctx.upper = string.upper(ctx.trimmed); return ctx end,
	function(ctx) ctx.length = #ctx.upper; return ctx end,
}

function Pipeline.process(raw)
	local ctx = { raw = raw }
	for i = 1, #stages do
		ctx = stages[i](ctx)
	end
	return ctx
end

return Pipeline
