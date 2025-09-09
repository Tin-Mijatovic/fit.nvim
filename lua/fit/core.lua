local uv = vim.uv or vim.loop
local M = {}

local timer = nil
local exercises_list = {}
local available_exercises = {}
local DEFAULT_REMINDER_INTERVAL_MS = 10 * 1000
local SNOOZE_INTERVAL_MS = 3 * 1000

-- Deep copy
local function deepcopy(orig, seen)
	seen = seen or {}
	local orig_type = type(orig)
	local copy
	if orig_type == "table" then
		if seen[orig] then
			return seen[orig]
		end
		copy = {}
		seen[orig] = copy
		for k, v in pairs(orig) do
			copy[deepcopy(k, seen)] = deepcopy(v, seen)
		end
	else
		copy = orig
	end
	return copy
end

-- Fisher–Yates shuffle
local function shuffle(tbl)
	for i = #tbl, 2, -1 do
		local j = math.random(1, i)
		tbl[i], tbl[j] = tbl[j], tbl[i]
	end
end

-- Stop timer
local function stop_timer()
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
end

-- Start timer
local function start_timer_internal(delay_ms, repeat_ms)
	stop_timer()
	if not uv then
		vim.notify("❌ Fit.nvim: vim.uv not found.", vim.log.ERROR, { title = "Fit.nvim" })
		return
	end
	timer = uv.new_timer()
	timer:start(
		delay_ms,
		repeat_ms,
		vim.schedule_wrap(function()
			M.show_reminder()
		end)
	)
end

-- Next exercise
local function get_next_exercise()
	if #available_exercises == 0 then
		available_exercises = deepcopy(exercises_list)
		if M.randomize then
			shuffle(available_exercises)
		end
		vim.notify("🔄 Fit.nvim: Restarting exercise cycle!", vim.log.INFO, { title = "Fit.nvim" })
		if #exercises_list == 0 then
			return { name = "No exercises configured!", description = "" }
		end
	end

	local ex = table.remove(available_exercises, 1) -- pick next in order
	return ex
end

-- Show the actual selection after lock is done
local function show_select(current_exercise)
	local msg = "💪 Time to exercise: " .. current_exercise.name
	if current_exercise.description ~= "" then
		msg = msg .. " (" .. current_exercise.description .. ")"
	end

	local actions = { "Done", "Postpone" }

	vim.ui.select(
		actions,
		{
			prompt = msg,
			win_config = {
				relative = "editor",
				width = 60,
				height = 7,
				border = "rounded",
				title = "Fit Reminder",
			},
		},
		vim.schedule_wrap(function(choice)
			if choice == "Done" then
				vim.notify("✅ Fit.nvim: Great job!", vim.log.INFO, { title = "Fit.nvim" })
				start_timer_internal(M.current_reminder_interval_ms, 0)
			elseif choice == "Postpone" then
				vim.notify("😴 Fit.nvim: Reminding you later...", vim.log.WARN, { title = "Fit.nvim" })
				start_timer_internal(M.current_snooze_interval_ms, 0)
			else
				vim.notify("🤷 Fit.nvim: Reminder dismissed.", vim.log.INFO, { title = "Fit.nvim" })
				start_timer_internal(M.current_reminder_interval_ms, 0)
			end
		end)
	)
end

-- Floating lock window
local function show_lock_screen(seconds, exercise)
	local buf = vim.api.nvim_create_buf(false, true)
	local width = 40
	local height = 3
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = "Fit Reminder Lock",
	})

	local function update(count)
		local lines = {
			" ⚠️ Inputs are locked for " .. count .. " seconds ⚠️",
			"FIT REMINDER",
		}
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end

	update(seconds)

	local countdown = uv.new_timer()
	local remaining = seconds
	countdown:start(
		1000,
		1000,
		vim.schedule_wrap(function()
			remaining = remaining - 1
			if remaining > 0 then
				update(remaining)
			else
				countdown:stop()
				countdown:close()
				vim.api.nvim_win_close(win, true)
				show_select(exercise)
			end
		end)
	)
end

-- Public reminder entry
function M.show_reminder()
	stop_timer()
	local ex = get_next_exercise()
	show_lock_screen(5, ex) -- lock 5s then show select
end

-- Init
function M.init(opts)
	M.current_reminder_interval_ms = (opts.interval_minutes and opts.interval_minutes * 60 * 1000)
		or DEFAULT_REMINDER_INTERVAL_MS
	M.current_snooze_interval_ms = (opts.snooze_minutes and opts.snooze_minutes * 60 * 1000) or SNOOZE_INTERVAL_MS

	exercises_list = opts.exercises or {}
	if #exercises_list == 0 then
		exercises_list = { { name = "Take a break", description = "Stand and move" } }
	end

	M.randomize = opts.randomize or false

	math.randomseed(os.time())
	available_exercises = deepcopy(exercises_list)
	if M.randomize then
		shuffle(available_exercises)
	end

	vim.notify(
		"🏋️ Fit.nvim active. Next reminder in " .. (M.current_reminder_interval_ms / 1000 / 60) .. " minutes.",
		vim.log.INFO,
		{ title = "Fit.nvim" }
	)

	start_timer_internal(M.current_reminder_interval_ms + 200, 0)
end

function M.stop()
	stop_timer()
	vim.notify("⏹ Fit.nvim stopped.", vim.log.INFO, { title = "Fit.nvim" })
end

return M
