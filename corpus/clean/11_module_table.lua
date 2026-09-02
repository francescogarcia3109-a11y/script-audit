local M = {}
M.version = "1.4.2"
function M.add(a, b) return a + b end
function M.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
return M
