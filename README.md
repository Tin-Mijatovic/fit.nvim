# fit.nvim

🏋️ A simple Neovim plugin to remind you to take breaks and exercise!

Fit.nvim presents you with a random exercise reminder at a configurable interval. You can choose to "Done" the exercise (restarting the main timer) or "Postpone" (snooze for a shorter period).

---

<https://github.com/Tin-Mijatovic/fit.nvim>

---

## ✨ Features

* **Configurable Interval:** Set how often you want to be reminded (in minutes).
* **Snooze Functionality:** Postpone reminders for a shorter duration.
* **Randomized Exercises:** Presents a different exercise each time until all are shown, then restarts the cycle.
* **Interactive Prompt:** Uses `vim.ui.select` for a clear, central reminder.
* **Lightweight:** Pure Lua, minimal dependencies (just Neovim's built-in `vim.uv`/`vim.loop` and `vim.ui.select`).

## 🚀 Installation

Install with your favorite plugin manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim) (Recommended)

```lua
-- In your plugins/init.lua, or a dedicated local plugins file like lua/config/plugins/fit.lua
return {
  {
    "Tin-Mijatovic/fit.nvim", -- Use your GitHub repository directly
    lazy = false, -- CRUCIAL: Ensures the plugin loads at Neovim startup.
    opts = {
      interval_minutes = 10,        -- Required: Reminder interval in MINUTES (e.g., 10 minutes)
      snooze_minutes = 0.5,         -- Required: Snooze interval in MINUTES (e.g., 0.5 minutes = 30 seconds)
                                    -- Use fractions for seconds: 0.1 for 6s, 0.05 for 3s etc.

      exercises = {
        { name = "Push-ups", description = "10-15 reps" },
        { name = "Squats", description = "15-20 reps" },
        -- ... more exercises ...
      },
    },
  },
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
-- In your init.lua or lua/plugins.lua
use {
  "Tin-Mijatovic/fit.nvim", -- Use your GitHub repository directly
  config = function()
    require("fit").setup({
      interval_minutes = 10,
      snooze_minutes = 0.5,
      exercises = {
        { name = "Push-ups", description = "10-15 reps" },
        { name = "Squats", description = "15-20 reps" },
        -- ... more exercises ...
      },
    })
  end,
}
```

*Note: Packer does not have a `lazy` option for eager loading; `config` runs after the plugin is sourced.*

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
" In your init.vim or .vimrc
Plug 'Tin-Mijatovic/fit.nvim' " Use your GitHub repository directly

lua << EOF
  require("fit").setup({
    interval_minutes = 10,
    snooze_minutes = 0.5,
    exercises = {
      { name = "Push-ups", description = "10-15 reps" },
      { name = "Squats", description = "15-20 reps" },
      -- ... more exercises ...
    },
  })
EOF
```

*Note: `vim-plug` loads plugins on startup by default. The `lua << EOF` block runs after plugin sourcing.*

## ⚙️ Configuration

The plugin is configured via the `opts` table (for `lazy.nvim`) or the table passed to `require("fit").setup()` (for other managers).

* `interval_minutes` (number, **required**):
  * The primary interval (in minutes) after which you will receive an exercise reminder.
  * **Example:** `10` for every 10 minutes.
* `snooze_minutes` (number, **required**):
  * The shorter interval (in minutes) used when you choose to "Postpone" an exercise. Use fractions for seconds.
  * **Example:** `0.05` for 3 seconds (`0.05 * 60 = 3`).
* `exercises` (table, **required**):
  * A Lua table containing your list of exercises. Each entry in the table should be a table itself with:
    * `name` (string, **required**): The name of the exercise (e.g., "Push-ups").
    * `description` (string, *optional*): A brief description or rep count (e.g., "10-15 reps").

### Example `opts` configuration

```lua
opts = { -- This is the table you pass to setup()
  interval_minutes = 15,       -- Remind every 15 minutes
  snooze_minutes = 0.5,        -- Snooze for 30 seconds
  exercises = {
    { name = "Quick Stretch", description = "Upper body" },
    { name = "Walk Around", description = "2 minutes" },
  },
},
```

## 💡 Usage

Once installed and configured, `fit.nvim` will automatically start reminding you after your configured `interval_minutes` when Neovim launches.

When a reminder appears (using |vim.ui.select|):

* **Done:** Select this when you've completed the exercise. The main timer
    will restart for `interval_minutes`. A new exercise will be chosen for
    the next reminder.
* **Postpone:** Select this to delay the reminder. The timer will restart
    for `snooze_minutes`. A new exercise will be chosen.
* **Dismiss (e.g., pressing `<Esc>`):** The reminder timer will reset for
    `interval_minutes`. A new exercise will be chosen.

Exercise Cycling:
The plugin ensures that each exercise in your configured list is presented
at least once before any exercise is repeated. Once all exercises have been
shown, the cycle resets, and a new random sequence begins.

### API Commands (for advanced users/debugging)

You can interact with the plugin using Lua commands:

* `:lua require("fit").stop()`: Stops the reminder timer completely.
* `:lua require("fit").remind()`: Immediately triggers an exercise reminder, regardless of the active timer.

## 🤝 Contributing

Feel free to open issues or submit pull requests on the GitHub repository for new features, bug fixes, or improvements!

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
