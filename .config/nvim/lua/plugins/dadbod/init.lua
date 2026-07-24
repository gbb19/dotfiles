-- lua/plugins/dadbod/init.lua
-- Entry point for Neovim's dadbod configuration.
-- Configures autocommands, auto-connections, and routes buffer-local keymaps.

-- Add plugins using vim.pack
vim.pack.add({
  "https://github.com/tpope/vim-dadbod",
})

-- Suppress dadbod's built-in 'DB: Running query...' / 'DB: Query finished' echo messages
-- so we can replace them with Fidget spinner progress instead.
vim.g.db_ui_disable_info_notifications = 1

local M = {}
local state = require("plugins.dadbod.state")

-- Create custom setup autocommand group
local group = vim.api.nvim_create_augroup("DadbodCustomSetup", { clear = true })

function M.show_table_detail()
  return require("plugins.dadbod.hover").show_table_detail()
end

--- Updates or invalidates the cached last dbout file path for a SQL buffer
function M.update_last_result(sql_path, result_path)
  state.update_last_result(sql_path, result_path)
end

function M.open_last_result()
  return require("plugins.dadbod.results").open_last()
end

vim.api.nvim_create_user_command("DbInspectTables", function()
  require("plugins.dadbod.picker").inspect_tables()
end, { desc = "Inspect DB Schema & Tables (View Only)" })

local function setup_sql_buffer(args)
  require("plugins.dadbod.buffers").setup_sql(args, {
    auto_bind = require("plugins.dadbod.db").auto_bind,
    open_last_result = M.open_last_result,
    show_table_detail = M.show_table_detail,
  })
end

require("plugins.dadbod.autocmds").setup({
  group = group,
  setup_sql = setup_sql_buffer,
})

-- Force Neovim to always route *.dbout files to the "dbout" filetype.
vim.filetype.add({
  pattern = {
    [".*%.dbout"] = "dbout",
  },
})

-- Export public API functions for backwards compatibility if needed
M.run_sql_block = function() require("plugins.dadbod.query").run_sql_block() end
M.copy_block_as_csv = function() require("plugins.dadbod.query").copy_block_as_csv() end
M.copy_block_as_json = function() require("plugins.dadbod.query").copy_block_as_json() end
M.switch_connection = function() require("plugins.dadbod.db").switch_connection() end
M.browse_tables = function() require("plugins.dadbod.picker").browse_tables() end
M.inspect_tables = function() require("plugins.dadbod.picker").inspect_tables() end
M.switch_result_history = function() require("plugins.dadbod.history").switch_result_history() end
M.clear_all_results = function() require("plugins.dadbod.history").clear_all_results() end

-- Handle immediate load case if the buffer is already SQL or dbout
if vim.bo.filetype == "sql" then
  setup_sql_buffer()
elseif vim.bo.filetype == "dbout" then
  require("plugins.dadbod.buffers").setup_dbout()
end

return M
