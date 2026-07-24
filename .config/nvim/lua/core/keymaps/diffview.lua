-- Lazy load diffview on :Diffview* commands
local utils = require("core.utils")
local git_branches = require("core.git.branches")
local git_repo = require("core.git.repo")
local git_feature = require("core.git.feature")

vim.api.nvim_create_user_command("DiffviewOpen", function(opts)
  require("plugins.diffview")
  vim.api.nvim_del_user_command("DiffviewOpen")
  vim.cmd("DiffviewOpen " .. opts.args)
end, { nargs = "*" })

vim.api.nvim_create_user_command("DiffviewFileHistory", function(opts)
  require("plugins.diffview")
  vim.api.nvim_del_user_command("DiffviewFileHistory")
  vim.cmd("DiffviewFileHistory " .. opts.args)
end, { nargs = "*" })

-- Helper: find an existing diffview tabpage (shared by all open commands)
local function find_diffview_tabpage()
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype:match("^Diffview") then
        return tabpage
      end
    end
  end
  return nil
end

-- Helper: lazy load diffview then run command, reusing existing diffview tab if open
local function load_diffview(cmd)
  return function()
    local existing = find_diffview_tabpage()
    if existing then
      vim.api.nvim_set_current_tabpage(existing)
      return
    end
    require("plugins.diffview")
    vim.cmd(cmd)
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Base branch resolution: prompt user → cache until diffview is closed.
-- ─────────────────────────────────────────────────────────────────────────────

local _branch_cache = {}

local function cache_key()
  local root = git_repo.root() or vim.fn.getcwd()
  local br = git_repo.current_branch() or "HEAD"
  return root .. ":" .. br
end

vim.keymap.set("n", "<leader>gD", load_diffview("DiffviewOpen"), { desc = "Open Git Diffview" })
vim.keymap.set("n", "<leader>gx", function()
  require("plugins.diffview")
  vim.cmd("DiffviewClose")
  _branch_cache[cache_key()] = nil
end, { desc = "Close Git Diffview" })
vim.keymap.set(
  "n",
  "<leader>gh",
  load_diffview("DiffviewFileHistory --first-parent %"),
  { desc = "List File History (current file, clean)" }
)
vim.keymap.set(
  "n",
  "<leader>gH",
  load_diffview("DiffviewFileHistory --first-parent"),
  { desc = "List Project History (clean)" }
)

local _diff_branch_preview_timer = nil

-- Prompt user for base branch using Snacks picker, cache the result until diffview is closed.
local function resolve_base_branch(callback)
  local key = cache_key()

  if _branch_cache[key] then
    callback(_branch_cache[key])
    return
  end

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    snacks.picker({
      source = "git_branches",
      title = "Select Base Branch for Diff",
      finder = function(picker_opts, ctx)
        local root = ctx:git_root()
        return ctx.filter:filter(git_branches.list(root))
      end,
      format = function(item, picker)
        local a = Snacks.picker.util.align
        local ret = {}
        if item.current then
          table.insert(ret, { a("* ", 2), "SnacksPickerGitBranchCurrent" })
        else
          table.insert(ret, { a("  ", 2) })
        end
        table.insert(ret, { item.branch, "SnacksPickerGitBranch" })

        if not item.is_remote then
          local status_parts = {}
          if item.ahead then
            table.insert(status_parts, { "↑" .. item.ahead, "SnacksPickerGitAhead" })
          end
          if item.behind then
            if #status_parts > 0 then
              table.insert(status_parts, { " " })
            end
            table.insert(status_parts, { "↓" .. item.behind, "SnacksPickerGitBehind" })
          end
          if item.gone then
            table.insert(status_parts, { "[gone]", "SnacksPickerGitGone" })
          end

          if #status_parts > 0 then
            table.insert(ret, { " " })
            vim.list_extend(ret, status_parts)
          end
        end

        return ret
      end,
      preview = function(ctx)
        if not ctx.item or not ctx.item.branch then
          return
        end
        ctx.preview:set_title("Branch: " .. ctx.item.branch)
        if _diff_branch_preview_timer then
          pcall(vim.uv.timer_stop, _diff_branch_preview_timer)
          _diff_branch_preview_timer = nil
        end
        _diff_branch_preview_timer = vim.defer_fn(function()
          if ctx.picker and not ctx.picker.closed and ctx.buf and vim.api.nvim_buf_is_valid(ctx.buf) then
            local cmd = { "git", "-c", "core.quotepath=false", "--no-pager", "log", "-n", "15", "--stat", ctx.item.branch }
            pcall(require("snacks.picker.preview").cmd, cmd, ctx, { ft = "git" })
          end
        end, 80)
      end,
      confirm = function(picker, item)
        picker:close()
        if item and item.branch then
          _branch_cache[key] = item.branch
          callback(item.branch)
        end
      end,
    })
  else
    vim.ui.input({
      prompt = "Base branch: ",
      default = "origin/",
    }, function(input)
      if not input or input == "" then
        return
      end
      _branch_cache[key] = input
      callback(input)
    end)
  end
end

-- Reset cached base branch for the current repo/branch
vim.api.nvim_create_user_command("DiffviewResetBase", function()
  _branch_cache[cache_key()] = nil
  utils.notify("diffview_cache_cleared")
end, {})

-- Core open helper: reuse existing diffview tab or open new one with given base branch.
local function do_open_diffview(base_branch)
  utils.notify("diffview_open_diff", base_branch)
  require("plugins.diffview")
  local existing = find_diffview_tabpage()
  if existing then
    vim.api.nvim_set_current_tabpage(existing)
    return
  end
  vim.cmd("DiffviewOpen " .. base_branch .. "...")
end

-- Core file-history helper: same pattern as do_open_diffview
local function do_open_file_history(base_branch)
  utils.notify("diffview_open_history", base_branch)
  require("plugins.diffview")
  local existing = find_diffview_tabpage()
  if existing then
    vim.api.nvim_set_current_tabpage(existing)
    return
  end
  vim.cmd(string.format("DiffviewFileHistory --first-parent %s..HEAD %%", base_branch))
end

vim.keymap.set("n", "<leader>gov", function()
  resolve_base_branch(function(base)
    if base then
      do_open_diffview(base)
    end
  end)
end, { desc = "View PR / Branch Diff (Diffview)" })

vim.keymap.set("n", "<leader>goh", function()
  resolve_base_branch(function(base)
    if base then
      do_open_file_history(base)
    end
  end)
end, { desc = "View File PR History" })

-- Find the merge commit that introduced the commit of the current line, and open it in Diffview.
local function open_line_feature_diff()
  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" or vim.bo[bufnr].buftype ~= "" then
    utils.notify("buffer_no_name")
    return
  end

  local git_root = git_repo.root()
  if not git_root then
    utils.notify("git_not_repo")
    return
  end

  local result, err = git_feature.resolve_line_commit(file, vim.api.nvim_win_get_cursor(0)[1])
  if not result then
    utils.notify(err)
    return
  end

  require("plugins.diffview")
  utils.notify(result.kind == "merge" and "git_open_merge" or "git_open_commit", result.detail)
  vim.cmd("DiffviewOpen " .. result.commit .. "^!")
end

vim.keymap.set("n", "<leader>gm", open_line_feature_diff, { desc = "View Merge/Feature Diff for Current Line" })
