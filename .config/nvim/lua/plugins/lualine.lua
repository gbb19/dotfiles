-- Add lualine.nvim using built-in vim.pack
vim.pack.add({
  "https://github.com/nvim-lualine/lualine.nvim",
})


-- Custom Git Blame component for statusline (displays quietly at the bottom)
local function git_blame()
  local blame = vim.b.gitsigns_blame_line
  if not blame or blame == "" then
    return ""
  end
  return blame
end

-- Resolve active SQL buffer target (whether focused in SQL editor or dbout result window)
local function get_sql_target_buf()
  local cur_buf = vim.api.nvim_get_current_buf()
  if vim.bo[cur_buf].filetype == "sql" then
    return cur_buf
  end
  if vim.bo[cur_buf].filetype == "dbout" or vim.bo[cur_buf].filetype == "explain" then
    local sql_path = vim.b[cur_buf].sql_source_path
    if sql_path and sql_path ~= "" then
      local b = vim.fn.bufnr(sql_path)
      if b ~= -1 and vim.api.nvim_buf_is_valid(b) then
        return b
      end
    end
  end
  return nil
end

-- Custom DB status component (embeds atomic statusline highlight codes for 100% instant color sync)
local function db_status()
  local target_buf = get_sql_target_buf()
  if not target_buf then
    return ""
  end

  local profile = vim.b[target_buf].db_profile
  if not profile or profile == "" then
    return "%#LualineGitBlame#󰆼 NONE%*"
  end

  local name = profile:upper()
  local status = vim.b[target_buf].db_connection_status or "connected"

  local status_suffix = ""
  local hl_group = "DiagnosticInfo"

  if status == "connecting" then
    status_suffix = " [connecting...]"
    hl_group = "DiagnosticWarn"
  elseif status == "failed" then
    status_suffix = " [failed]"
    hl_group = "DiagnosticError"
  elseif status == "connected" then
    status_suffix = " [connected]"
    local is_prod = profile:lower():match("prod") or profile:lower():match("production")
    if is_prod then
      hl_group = "DiagnosticError"
    else
      hl_group = "DiagnosticInfo"
    end
  end

  local is_prod = profile:lower():match("prod") or profile:lower():match("production")
  local warning_suffix = is_prod and " WARNING" or ""
  local raw_text = "󰆼 " .. name .. status_suffix .. warning_suffix

  return string.format("%%#%s#%s%%*", hl_group, raw_text)
end

-- Custom DB runtime component (only displays on dbout and explain buffers)
local function db_runtime()
  local ft = vim.bo.filetype
  if ft ~= "dbout" and ft ~= "explain" then
    return ""
  end
  local runtime = vim.b.db_runtime
  if not runtime or runtime == "" then
    local db_info = vim.b.db
    if type(db_info) == "table" and db_info.runtime then
      runtime = string.format("%.3fs", db_info.runtime)
      vim.b.db_runtime = runtime
    end
  end
  if runtime and runtime ~= "" then
    return "Exec: " .. runtime
  end
  return ""
end

-- Configure lualine
local ok, lualine = pcall(require, "lualine")
if not ok then return end

lualine.setup({
  options = {
    theme = "onedark",
    globalstatus = true,   -- Force global statusline
    icons_enabled = false, -- Disable all file type and section icons
    component_separators = { left = "|", right = "|" },
    section_separators = { left = "", right = "" },
    disabled_filetypes = {
      statusline = { "DiffviewFiles", "DiffviewFileHistory", "qf" },
      winbar = {
        "DiffviewFiles",
        "DiffviewFileHistory",
        "diffview",
        "qf",
        "toggleterm",
        "terminal",
        "snacks_picker",
        "snacks_input",
        "overseer_list",
      },
    },
  },
  sections = {
    lualine_a = { "mode" },
    lualine_b = { "branch", "diff", "diagnostics" },
    lualine_c = {},
    lualine_x = {
      db_status,
      {
        git_blame,
        color = "LualineGitBlame", -- Defined centrally in lua/plugins/theme.lua
      },
    },
    lualine_y = { "progress" },
    lualine_z = { "location" },
  },
  winbar = {
    lualine_c = {
      {
        "filename",
        path = 1,            -- Relative path
        separator = "",      -- No separator needed in winbar
        color = { gui = "bold" },
      },
      {
        db_runtime,
        color = "LualineGitBlame", -- Soft, subtle dimmed gray (reused from theme.lua)
      },
    },
  },
  inactive_winbar = {
    lualine_c = {
      {
        "filename",
        path = 1,
        color = "LualineGitBlame", -- Reuse dimmed gray defined in theme.lua
      },
      {
        db_runtime,
        color = "LualineGitBlame",
      },
    },
  },
})

-- Force instant lualine status refresh when switching between buffers/windows
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "BufWinEnter" }, {
  pattern = "*",
  callback = function()
    local ft = vim.bo.filetype
    if ft == "sql" or ft == "dbout" or ft == "explain" then
      pcall(function() require("lualine").refresh() end)
    end
  end,
})
