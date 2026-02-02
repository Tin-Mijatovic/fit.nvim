-- ~/Documents/Projects/fit.nvim/lua/fit/init.lua

local M = {}

local core = require("fit.core")

function M.setup(opts)
	core.init(opts)

	vim.api.nvim_create_user_command("FitToggle", function()
		M.toggle()
	end, { desc = "Toggle Fit.nvim reminder timer" })

	vim.api.nvim_create_user_command("FitStats", function()
		M.show_stats()
	end, { desc = "Show Fit.nvim statistics" })

	vim.api.nvim_create_user_command("FitLog", function()
		M.show_log()
	end, { desc = "Show Fit.nvim analytics and history" })

	vim.api.nvim_create_user_command("FitReset", function()
		M.reset()
	end, { desc = "Reset Fit.nvim statistics and history" })

	vim.api.nvim_create_user_command("FitStop", function()
		M.stop()
	end, { desc = "Stop Fit.nvim reminder timer" })

	vim.api.nvim_create_user_command("FitRemind", function()
		M.remind()
	end, { desc = "Trigger Fit.nvim reminder immediately" })
end

function M.stop()
	core.stop()
end

function M.remind()
	core.show_reminder()
end

function M.toggle()
	core.toggle()
end

function M.show_stats()
	core.show_stats()
end

function M.show_log()
	core.show_log()
end

function M.reset()
	core.reset()
end

return M
