local M = {}
local utils = require("core.utils")
local git_branches = require("core.git.branches")
local git_repo = require("core.git.repo")
local git_feature = require("core.git.feature")

local branch_cache = {}
local preview_timer

local function cache_key()
  return (git_repo.root() or vim.fn.getcwd())
    .. ":"
    .. (git_repo.current_branch() or "HEAD")
end

local function find_tab()
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype:match("^Diffview") then
        return tabpage
      end
    end
  end
end

function M.open_command(command)
  local tabpage = find_tab()
  if tabpage then
    vim.api.nvim_set_current_tabpage(tabpage)
    return
  end
  require("plugins.diffview")
  vim.cmd(command)
end

function M.close()
  require("plugins.diffview")
  vim.cmd("DiffviewClose")
  branch_cache[cache_key()] = nil
end

function M.reset_base()
  branch_cache[cache_key()] = nil
  utils.notify("diffview_cache_cleared")
end

local function format_branch(item)
  local align = Snacks.picker.util.align
  local result = {
    item.current
        and { align("* ", 2), "SnacksPickerGitBranchCurrent" }
      or { align("  ", 2) },
    { item.branch, "SnacksPickerGitBranch" },
  }
  if item.is_remote then return result end

  local status = {}
  if item.ahead then status[#status + 1] = { "↑" .. item.ahead, "SnacksPickerGitAhead" } end
  if item.behind then
    if #status > 0 then status[#status + 1] = { " " } end
    status[#status + 1] = { "↓" .. item.behind, "SnacksPickerGitBehind" }
  end
  if item.gone then status[#status + 1] = { "[gone]", "SnacksPickerGitGone" } end
  if #status > 0 then
    result[#result + 1] = { " " }
    vim.list_extend(result, status)
  end
  return result
end

local function resolve_base(callback)
  local key = cache_key()
  if branch_cache[key] then
    callback(branch_cache[key])
    return
  end

  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker then
    vim.ui.input({ prompt = "Base branch: ", default = "origin/" }, function(input)
      if not input or input == "" then return end
      branch_cache[key] = input
      callback(input)
    end)
    return
  end

  snacks.picker({
    source = "git_branches",
    title = "Select Base Branch for Diff",
    finder = function(_, ctx)
      return ctx.filter:filter(git_branches.list(ctx:git_root()))
    end,
    format = format_branch,
    preview = function(ctx)
      if not ctx.item or not ctx.item.branch then return end
      ctx.preview:set_title("Branch: " .. ctx.item.branch)
      if preview_timer then
        pcall(vim.uv.timer_stop, preview_timer)
        preview_timer = nil
      end
      preview_timer = vim.defer_fn(function()
        if ctx.picker and not ctx.picker.closed and ctx.buf and vim.api.nvim_buf_is_valid(ctx.buf) then
          local command = {
            "git", "-c", "core.quotepath=false", "--no-pager",
            "log", "-n", "15", "--stat", ctx.item.branch,
          }
          pcall(require("snacks.picker.preview").cmd, command, ctx, { ft = "git" })
        end
      end, 80)
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.branch then
        branch_cache[key] = item.branch
        callback(item.branch)
      end
    end,
  })
end

function M.open_branch_diff()
  resolve_base(function(base)
    utils.notify("diffview_open_diff", base)
    M.open_command("DiffviewOpen " .. base .. "...")
  end)
end

function M.open_branch_history()
  resolve_base(function(base)
    utils.notify("diffview_open_history", base)
    M.open_command(string.format("DiffviewFileHistory --first-parent %s..HEAD %%", base))
  end)
end

function M.open_line_feature_diff()
  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" or vim.bo[bufnr].buftype ~= "" then
    utils.notify("buffer_no_name")
    return
  end
  if not git_repo.root() then
    utils.notify("git_not_repo")
    return
  end

  local result, err = git_feature.resolve_line_commit(file, vim.api.nvim_win_get_cursor(0)[1])
  if not result then
    utils.notify(err)
    return
  end
  utils.notify(result.kind == "merge" and "git_open_merge" or "git_open_commit", result.detail)
  M.open_command("DiffviewOpen " .. result.commit .. "^!")
end

return M
