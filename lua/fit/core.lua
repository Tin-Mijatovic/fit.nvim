local uv = vim.uv or vim.loop

local DEFAULT_REMINDER_INTERVAL_MS = 10 * 1000
local SNOOZE_INTERVAL_MS = 3 * 1000

local notification_levels = {
	error = vim.log.ERROR,
	warning = vim.log.WARN,
	info = vim.log.INFO,
	debug = vim.log.DEBUG,
}

local function get_log_level(level_str)
	return notification_levels[level_str] or vim.log.INFO
end

local function create_module()
	local timer = nil
	local exercises_list = {}
	local available_exercises = {}
	local stats = {
		completed = 0,
		postponed = 0,
		dismissed = 0,
		total = 0,
	}

	local current_reminder_interval_ms = 0
	local current_snooze_interval_ms = 0
	local lock_seconds = 5
	local randomize = false
	local notification_level = "info"
	local log_file_path = vim.fn.stdpath("data") .. "/fit_stats.json"
	local stats_history = {}
	local last_notification_id = nil
	local last_summary_notification_id = nil
	local last_user_interaction = os.time()
	local idle_check_minutes = 0
	local active_reminder = false
	local notification_pending_response = false

	local M = {}
	local get_next_exercise
	local start_timer_internal
	local show_select

	local function trim_name(name, max_len)
		name = name or "(unknown)"
		if #name > max_len then
			return name:sub(1, max_len - 3) .. "..."
		end
		return name
	end

	local function parse_timestamp(ts)
		if type(ts) ~= "string" then
			return os.time()
		end
		local y, mo, d, h, mi, s = ts:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
		if y then
			return os.time({
				year = tonumber(y),
				month = tonumber(mo),
				day = tonumber(d),
				hour = tonumber(h),
				min = tonumber(mi),
				sec = tonumber(s),
				isdst = false,
			})
		end
		return os.time()
	end

	local function today_summary()
		local today = os.date("!%Y-%m-%d")
		local counts = {}
		local total = 0

		for _, entry in ipairs(stats_history or {}) do
			if entry.action == "completed" and entry.timestamp then
				local t = parse_timestamp(entry.timestamp)
				if os.date("!%Y-%m-%d", t) == today then
					total = total + 1
					local name = entry.exercise or "(unknown)"
					counts[name] = (counts[name] or 0) + 1
				end
			end
		end

		local lines = { string.format("Today completed: %d", total) }

		if total == 0 then
			return lines
		end

		local list = {}
		for name, cnt in pairs(counts) do
			table.insert(list, { name = name, count = cnt })
		end
		table.sort(list, function(a, b)
			return (b.count or 0) < (a.count or 0)
		end)

		local max_items = math.min(5, #list)
		for i = 1, max_items do
			local item = list[i]
			table.insert(lines, string.format("  • %s (%d)", trim_name(item.name, 28), item.count))
		end

		return lines
	end
	local record_stat
	local show_select

	local function dismiss_previous_notification()
		if last_notification_id then
			vim.notify("", { id = last_notification_id, hide = true })
			last_notification_id = nil
		end
	end

	local function dismiss_summary_notification()
		if last_summary_notification_id then
			vim.notify("", { id = last_summary_notification_id, hide = true })
			last_summary_notification_id = nil
		end
	end

	local function update_user_interaction()
		last_user_interaction = os.time()
	end

	local function shuffle(tbl)
		for i = #tbl, 2, -1 do
			local j = math.random(1, i)
			tbl[i], tbl[j] = tbl[j], tbl[i]
		end
	end

	local function stop_timer()
		if timer then
			timer:stop()
			timer:close()
			timer = nil
		end
	end

	local function show_lock_screen(seconds, exercise)
		dismiss_previous_notification()
		active_reminder = true
		notification_pending_response = true

		local buf = vim.api.nvim_create_buf(false, true)
		local width = 40
		local height = 3
		local col = math.floor((vim.o.columns - width) / 2)
		local row = math.floor((vim.o.lines - height) / 2)

		local _win = vim.api.nvim_open_win(buf, true, {
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
					vim.api.nvim_win_close(_win, true)
					show_select(exercise)
				end
			end)
		)
	end

show_select = function(current_exercise)
		dismiss_previous_notification()
		dismiss_summary_notification()

		local msg = "💪 Time to exercise: " .. current_exercise.name
		if current_exercise.description ~= "" then
			msg = msg .. " (" .. current_exercise.description .. ")"
		end

		local summary_lines = today_summary()
		if summary_lines and #summary_lines > 0 then
			local summary_id = vim.notify(
				table.concat(summary_lines, "\n"),
				vim.log.INFO,
				{ title = "Fit Today", timeout = 20000 }
			)
			if summary_id then
				last_summary_notification_id = summary_id
			end
		end

		local notification_result = vim.notify(msg, vim.log.INFO, { title = "Fit.nvim" })
		if notification_result then
			last_notification_id = notification_result
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
				update_user_interaction()
				notification_pending_response = false
				active_reminder = false
				dismiss_summary_notification()

				if choice == "Done" then
					stats.completed = stats.completed + 1
					stats.total = stats.total + 1
					record_stat("completed", current_exercise.name, nil)
					vim.notify("✅ Fit.nvim: Great job!", vim.log.INFO, { title = "Fit.nvim" })
					start_timer_internal(current_reminder_interval_ms, 0)
				elseif choice == "Postpone" then
					stats.postponed = stats.postponed + 1
					stats.total = stats.total + 1
					record_stat("postponed", current_exercise.name, nil)
					vim.notify("😴 Fit.nvim: Reminding you later...", vim.log.WARN, { title = "Fit.nvim" })
					start_timer_internal(current_snooze_interval_ms, 0)
				else
					stats.dismissed = stats.dismissed + 1
					stats.total = stats.total + 1
					record_stat("dismissed", current_exercise.name, nil)
					vim.notify("🤷 Fit.nvim: Reminder dismissed.", vim.log.INFO, { title = "Fit.nvim" })
					start_timer_internal(current_reminder_interval_ms, 0)
				end
			end)
		)
	end

	local function ensure_log_dir()
		local dir = log_file_path:match("(.+)/[^/]*$")
		if dir and uv.fs_stat(dir) == nil then
			uv.fs_mkdir(dir, 448) -- 0700
		end
	end

	local function save_stats_to_file()
		local success = pcall(function()
			ensure_log_dir()
			local file = io.open(log_file_path, "w")
			if not file then
				return false
			end
			file:write(vim.fn.json_encode(stats_history))
			file:close()
			return true
		end)

		if not success then
			vim.notify(
				"❌ Fit.nvim: Failed to save stats to " .. log_file_path,
				vim.log.ERROR,
				{ title = "Fit.nvim" }
			)
		end
	end

	local function load_stats_from_file()
		local ok, data = pcall(function()
			local file = io.open(log_file_path, "r")
			if not file then
				return {}
			end
			local content = file:read("*a")
			file:close()

			if not content or content == "" then
				return {}
			end

			local decoded = vim.fn.json_decode(content)
			return type(decoded) == "table" and decoded or {}
		end)

		if not ok then
			vim.notify(
				"❌ Fit.nvim: Failed to load stats from " .. log_file_path,
				vim.log.WARN,
				{ title = "Fit.nvim" }
			)
			return {}
		end

		return data
	end

	record_stat = function(action, exercise_name, reps)
		local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
		table.insert(stats_history, {
			timestamp = now,
			action = action,
			exercise = exercise_name,
			reps = reps,
		})
		save_stats_to_file()
	end

	local function get_period_stats(period)
		local now = os.time()
		local entries = {}

		for _, entry in ipairs(stats_history) do
			local entry_time = entry.timestamp and parse_timestamp(entry.timestamp) or now

			local include = false
			local seconds_diff = now - entry_time

			if period == "today" then
				local entry_date = os.date("!%Y-%m-%d", entry_time)
				local now_date = os.date("!%Y-%m-%d", now)
				include = entry_date == now_date
			elseif period == "day" then
				include = seconds_diff <= 24 * 3600
			elseif period == "week" then
				include = seconds_diff <= 7 * 24 * 3600
			elseif period == "month" then
				local entry_month = os.date("!%Y-%m", entry_time)
				local now_month = os.date("!%Y-%m", now)
				include = entry_month == now_month
			elseif period == "year" then
				local entry_year = os.date("!%Y", entry_time)
				local now_year = os.date("!%Y", now)
				include = entry_year == now_year
			elseif period == "all" then
				include = true
			end

			if include then
				table.insert(entries, entry)
			end
		end

		local completed = 0
		local postponed = 0
		local dismissed = 0
		local total = 0

		local exercise_counts = {}

		for _, entry in ipairs(entries) do
			total = total + 1
			if entry.action == "completed" then
				completed = completed + 1
				local ex_name = entry.exercise or "Unknown"
				exercise_counts[ex_name] = (exercise_counts[ex_name] or 0) + 1
			elseif entry.action == "postponed" then
				postponed = postponed + 1
			elseif entry.action == "dismissed" then
				dismissed = dismissed + 1
			end
		end

		return {
			period = period,
			total = total,
			completed = completed,
			postponed = postponed,
			dismissed = dismissed,
			completion_rate = total > 0 and math.floor((completed / total) * 100) or 0,
			entries = entries,
			exercise_counts = exercise_counts,
		}
	end

	local function create_bar(value, max_value, width)
		if max_value == 0 then
			max_value = 1
		end
		local filled = math.floor((value / max_value) * width)
		local bar = string.rep("█", filled)
		bar = bar .. string.rep("░", width - filled)
		return bar
	end

	local function create_donut_chart(completed, total)
		if total == 0 then
			return "⚪"
		end
		local percentage = completed / total

		local donut = {
			"⚪",
			"◐",
			"◑",
			"⚫",
		}

		if percentage < 0.25 then
			return donut[1]
		elseif percentage < 0.5 then
			return donut[2]
		elseif percentage < 0.75 then
			return donut[3]
		else
			return donut[4]
		end
	end

	local function create_stacked_bar(completed, postponed, dismissed, width)
		local total = completed + postponed + dismissed
		if total == 0 then
			return string.rep("░", width)
		end

		local function seg(len, char)
			if len <= 0 then
				return ""
			end
			return string.rep(char, len)
		end

		local c_len = math.floor((completed / total) * width + 0.5)
		local p_len = math.floor((postponed / total) * width + 0.5)
		local d_len = width - c_len - p_len

		return seg(c_len, "█") .. seg(p_len, "▓") .. seg(d_len, "░")
	end

	get_next_exercise = function()
		if #available_exercises == 0 then
			available_exercises = vim.deepcopy(exercises_list)
			if randomize then
				shuffle(available_exercises)
			end
			vim.notify("🔄 Fit.nvim: Restarting exercise cycle!", vim.log.INFO, { title = "Fit.nvim" })
			if #exercises_list == 0 then
				return { name = "No exercises configured!", description = "" }
			end
		end

		local ex = table.remove(available_exercises, 1)
		return ex
	end

	local function start_timer_internal_impl(delay_ms, repeat_ms)
		stop_timer()

		if idle_check_minutes > 0 then
			local idle_seconds = os.time() - last_user_interaction
			if idle_seconds > idle_check_minutes * 60 then
				timer = uv.new_timer()
				timer:start(
					delay_ms,
					repeat_ms,
					vim.schedule_wrap(function()
						start_timer_internal_impl(delay_ms, repeat_ms)
					end)
				)
				return
			end
		end

		if not uv then
			vim.notify(
				"❌ Fit.nvim: vim.uv not found.",
				get_log_level(notification_level),
				{ title = "Fit.nvim" }
			)
			return
		end

		timer = uv.new_timer()
		timer:start(
			delay_ms,
			repeat_ms,
			vim.schedule_wrap(function()
				stop_timer()
				local ex = get_next_exercise()
				show_lock_screen(lock_seconds, ex)
			end)
		)
	end

	start_timer_internal = start_timer_internal_impl

	local function show_log()
		local current_period = "day"
		local periods = { "day", "week", "month", "year", "all" }
		local period_index = 1

		local buf = vim.api.nvim_create_buf(false, true)

		local function render_header()
			local lines = {
				"",
				"🏋️  Fit.nvim Analytics",
				"────────────────────────",
				"",
				"Press Tab or click to switch period",
				"",
			}
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		end

		local function render_stats(period)
			local stats_data = get_period_stats(period)

			local lines = {
				"",
				"🏋️  Fit.nvim Analytics - " .. string.upper(period),
				"────────────────────────",
				"",
				"  📊 Summary:",
				"──────────────────────",
				"  Total reminders:    " .. tostring(stats_data.total),
				"  ✅ Completed:        " .. tostring(stats_data.completed),
				"  😴 Postponed:        " .. tostring(stats_data.postponed),
				"  🤷 Dismissed:        " .. tostring(stats_data.dismissed),
				"──────────────────────",
				"  Completion rate:     " .. stats_data.completion_rate .. "%",
				"",
				"  📈 Progress:  " .. create_donut_chart(stats_data.completed, stats_data.total),
				"  🧭 Distribution: " .. create_stacked_bar(stats_data.completed, stats_data.postponed, stats_data.dismissed, 30),
				"  (█ done | ▓ postponed | ░ dismissed)",
				"──────────────────────",
				"",
			}

			if #stats_data.entries > 0 then
				table.insert(lines, "")
				table.insert(lines, "  💪 Exercises Done:")
				table.insert(lines, "──────────────────────")
				table.insert(lines, "")

			local sorted_exercises = {}
			for ex_name, count in pairs(stats_data.exercise_counts or {}) do
				table.insert(sorted_exercises, { name = ex_name, count = tonumber(count) or 0 })
			end

			table.sort(sorted_exercises, function(a, b)
				return (b.count or 0) < (a.count or 0)
			end)

			local function fit_name(name)
				name = name or "(unknown)"
				if #name > 22 then
					return name:sub(1, 19) .. "..."
				end
				return name
			end

				for i, ex in ipairs(sorted_exercises) do
					if i <= 10 then
						local bar = create_bar(ex.count, sorted_exercises[1].count, 10)
						table.insert(lines, string.format("  %2d. %-22s %s  (%d)", i, fit_name(ex.name), bar, ex.count))
					end
				end

				if #sorted_exercises > 10 then
					table.insert(lines, "")
					table.insert(lines, string.format("  ... and %d more exercises", #sorted_exercises - 10))
				end
			else
				table.insert(lines, "")
				table.insert(lines, "  No exercises completed in this period")
			end

			table.insert(lines, "")
			table.insert(lines, "──────────────────────")
			table.insert(lines, "  Press q or <Esc> to close")

			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		end

		local function render_help()
			local lines = {
				"",
				"🏋️  Fit.nvim Analytics - Help",
				"────────────────────────",
				"",
				"  Commands:",
				"──────────────────────",
				"  :FitLog      - Show this analytics window",
				"  :FitStats    - Show current session stats",
				"  :FitToggle   - Start/stop reminder timer",
				"  :FitStop     - Stop reminder timer",
				"  :FitRemind   - Trigger immediate reminder",
				"",
				"  Keys:",
				"──────────────────────",
				"  Tab / S-Tab   - Next period",
				"  Shift-Tab      - Previous period",
				"  q / <Esc>      - Close window",
				"",
				"  Configuration:",
				"──────────────────────",
				"  log_file_path: " .. log_file_path,
				"",
			}
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		end

		local function render_current_tab()
			if current_period == "help" then
				render_help()
			else
				render_stats(current_period)
			end
		end

		render_current_tab()

		local width = 80
		local height = #vim.api.nvim_buf_get_lines(buf, 0, -1, false)
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
			title = "Fit Analytics - " .. string.upper(current_period),
		})

		local function set_title()
			if vim.api.nvim_win_set_title then
				vim.api.nvim_win_set_title(win, "Fit Analytics - " .. string.upper(current_period))
			end
		end

		vim.keymap.set("n", "<Tab>", function()
			period_index = period_index % #periods + 1
			current_period = periods[period_index]
			set_title()
			render_current_tab()
		end, { buffer = buf })

		vim.keymap.set("n", "<S-Tab>", function()
			period_index = (period_index - 2 + #periods) % #periods + 1
			current_period = periods[period_index]
			set_title()
			render_current_tab()
		end, { buffer = buf })

		vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
		vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
	end

	function M.init(opts)
		if type(opts) ~= "table" then
			vim.notify("❌ Fit.nvim: Invalid configuration. Expected a table.", vim.log.ERROR, { title = "Fit.nvim" })
			return
		end

		if opts.interval_minutes == nil or type(opts.interval_minutes) ~= "number" or opts.interval_minutes <= 0 then
			vim.notify(
				"❌ Fit.nvim: interval_minutes must be a positive number.",
				vim.log.ERROR,
				{ title = "Fit.nvim" }
			)
			return
		end

		if opts.snooze_minutes == nil or type(opts.snooze_minutes) ~= "number" or opts.snooze_minutes < 0 then
			vim.notify(
				"❌ Fit.nvim: snooze_minutes must be a non-negative number.",
				vim.log.ERROR,
				{ title = "Fit.nvim" }
			)
			return
		end

		if opts.exercises == nil or type(opts.exercises) ~= "table" then
			vim.notify(
				"❌ Fit.nvim: exercises must be a table of exercise entries.",
				vim.log.ERROR,
				{ title = "Fit.nvim" }
			)
			return
		end

		for i, exercise in ipairs(opts.exercises) do
			if type(exercise) ~= "table" or type(exercise.name) ~= "string" or exercise.name == "" then
				vim.notify(
					"❌ Fit.nvim: Exercise #" .. i .. " must have a valid 'name' field.",
					vim.log.ERROR,
					{ title = "Fit.nvim" }
				)
				return
			end
		end

		if opts.randomize ~= nil and type(opts.randomize) ~= "boolean" then
			vim.notify(
				"❌ Fit.nvim: randomize must be a boolean.",
				vim.log.ERROR,
				{ title = "Fit.nvim" }
			)
			return
		end

		if opts.lock_seconds ~= nil and (type(opts.lock_seconds) ~= "number" or opts.lock_seconds < 0) then
			vim.notify(
				"❌ Fit.nvim: lock_seconds must be a non-negative number.",
				vim.log.ERROR,
				{ title = "Fit.nvim" }
			)
			return
		end

		if opts.notification_level ~= nil and type(opts.notification_level) ~= "string" then
			vim.notify(
				"❌ Fit.nvim: notification_level must be a string.",
				vim.log.ERROR,
				{ title = "Fit.nvim" }
			)
			return
		end

		if opts.log_file_path ~= nil and type(opts.log_file_path) ~= "string" then
			vim.notify(
				"❌ Fit.nvim: log_file_path must be a string.",
				vim.log.ERROR,
				{ title = "Fit.nvim" }
			)
			return
		end

		if opts.idle_check_minutes ~= nil and (type(opts.idle_check_minutes) ~= "number" or opts.idle_check_minutes < 0) then
			vim.notify(
				"❌ Fit.nvim: idle_check_minutes must be a non-negative number.",
				vim.log.ERROR,
				{ title = "Fit.nvim" }
			)
			return
		end

		current_reminder_interval_ms = (opts.interval_minutes and opts.interval_minutes * 60 * 1000) or DEFAULT_REMINDER_INTERVAL_MS
		current_snooze_interval_ms = (opts.snooze_minutes and opts.snooze_minutes * 60 * 1000) or SNOOZE_INTERVAL_MS
		lock_seconds = opts.lock_seconds or 5
		notification_level = opts.notification_level or "info"
		log_file_path = opts.log_file_path or vim.fn.stdpath("data") .. "/fit_stats.json"
		idle_check_minutes = opts.idle_check_minutes or 0

		vim.api.nvim_create_autocmd("CursorMoved", {
			callback = function()
				update_user_interaction()
			end,
		})

		vim.api.nvim_create_autocmd("BufEnter", {
			callback = function()
				update_user_interaction()
			end,
		})

		exercises_list = opts.exercises or {}
		if #exercises_list == 0 then
			exercises_list = { { name = "Take a break", description = "Stand and move" } }
		end

		randomize = opts.randomize or false

		stats_history = load_stats_from_file() or {}

		math.randomseed(os.time())
		available_exercises = vim.deepcopy(exercises_list)
		if randomize then
			shuffle(available_exercises)
		end

		vim.notify(
			"🏋️ Fit.nvim active. Next reminder in " .. (current_reminder_interval_ms / 1000 / 60) .. " minutes.",
			vim.log.INFO,
			{ title = "Fit.nvim" }
		)

		start_timer_internal(current_reminder_interval_ms + 200, 0)
	end

	function M.stop()
		stop_timer()
		vim.notify("⏹ Fit.nvim stopped.", vim.log.INFO, { title = "Fit.nvim" })
	end

	function M.toggle()
		if timer then
			M.stop()
		else
			start_timer_internal(current_reminder_interval_ms, 0)
			vim.notify("▶️ Fit.nvim started.", vim.log.INFO, { title = "Fit.nvim" })
		end
	end

	function M.show_reminder()
		stop_timer()
		local ex = get_next_exercise()
		show_lock_screen(lock_seconds, ex)
	end

	function M.show_stats()
		local completion_rate = stats.total > 0 and math.floor((stats.completed / stats.total) * 100) or 0

		local lines = {
			"",
			"🏋️  Fit.nvim Stats",
			"─────────────────────",
			"  Total reminders:    " .. tostring(stats.total),
			"  ✅ Completed:        " .. tostring(stats.completed),
			"  😴 Postponed:        " .. tostring(stats.postponed),
			"  🤷 Dismissed:        " .. tostring(stats.dismissed),
			"─────────────────────",
			"  Completion rate:     " .. completion_rate .. "%",
			"",
		}

		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

		local width = 25
		local height = #lines
		local col = math.floor((vim.o.columns - width) / 2)
		local row = math.floor((vim.o.lines - height) / 2)

		local _win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			style = "minimal",
			border = "rounded",
			title = "Fit Stats",
		})

		vim.api.nvim_buf_set_option(buf, "modifiable", false)
		vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
		vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
	end

	M.show_log = show_log

	function M.reset()
		stats = { completed = 0, postponed = 0, dismissed = 0, total = 0 }
		stats_history = {}
		save_stats_to_file()
		vim.notify("🔄 Fit.nvim stats reset.", vim.log.INFO, { title = "Fit.nvim" })
	end

	return M
end

local M = create_module()

return M
