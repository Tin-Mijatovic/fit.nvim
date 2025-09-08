-- ~/Documents/Projects/fit.nvim/lua/fit/init.lua

local M = {}

local core = require("fit.core")

function M.setup(opts)
	core.init(opts)
end

function M.stop()
	core.stop()
end

function M.remind()
	core.show_reminder()
end

-- --- STATS: New public API for showing stats ---
function M.show_stats()
	core.show_stats()
end

return M
