-- Lazy load diffview on :Diffview* commands
local utils = require("core.utils")

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

local function git_root()
  local root = vim.trim(vim.fn.system({ "git", "rev-parse", "--show-toplevel" }))
  return (vim.v.shell_error == 0 and root ~= "") and root or nil
end

local function current_branch()
  local br = vim.trim(vim.fn.system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }))
  return (vim.v.shell_error == 0 and br ~= "") and br or nil
end

local function cache_key()
  local root = git_root() or vim.fn.getcwd()
  local br = current_branch() or "HEAD"
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
        local items = {}

        -- 1. Local branches (sorted by committerdate: most recent first)
        local local_out = vim.fn.systemlist({ "git", "-c", "core.quotepath=false", "branch", "--no-color", "-vv", "--sort=-committerdate" })
        if vim.v.shell_error == 0 then
          for _, line in ipairs(local_out) do
            if line ~= "" and not line:find("HEAD%s*%->") then
              local status, branch = line:match("^(.)%s+(%S+)")
              if branch then
                table.insert(items, {
                  text = branch,
                  branch = branch,
                  commit = branch,
                  is_remote = false,
                  cwd = root,
                  current = status == "*",
                })
              end
            end
          end
        end

        -- 2. Remote branches (sorted by committerdate: most recent first)
        local remote_out = vim.fn.systemlist({ "git", "-c", "core.quotepath=false", "branch", "--no-color", "-r", "--sort=-committerdate" })
        if vim.v.shell_error == 0 then
          for _, line in ipairs(remote_out) do
            local trimmed = vim.trim(line)
            if trimmed ~= "" and not trimmed:find("HEAD%s*%->") then
              table.insert(items, {
                text = trimmed,
                branch = trimmed,
                commit = trimmed,
                is_remote = true,
                cwd = root,
                current = false,
              })
            end
          end
        end

        return ctx.filter:filter(items)
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
            pcall(require("snacks.picker.preview").git_show, ctx)
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

  local git_root = vim.trim(vim.fn.system({ "git", "rev-parse", "--show-toplevel" }))
  if vim.v.shell_error ~= 0 or git_root == "" then
    utils.notify("git_not_repo")
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local blame_out = vim.fn.system({
    "git", "blame",
    "-L", string.format("%d,%d", line, line),
    "--porcelain",
    file
  })
  if vim.v.shell_error ~= 0 or blame_out == "" then
    utils.notify("git_blame_failed")
    return
  end

  local commit = blame_out:match("^(%x+)")
  if not commit or commit:match("^0+$") then
    utils.notify("git_uncommitted")
    return
  end

  -- List of base branches to check, in order of early integration to late integration
  local base_branches = {
    "dev", "develop", "origin/dev", "origin/develop",
    "master", "main", "origin/master", "origin/main",
    "staging", "origin/staging",
    "HEAD"
  }

  -- Filter base branches to only those that exist and contain the commit
  local candidate_branches = {}
  for _, br in ipairs(base_branches) do
    vim.fn.system({ "git", "rev-parse", "--verify", br })
    if vim.v.shell_error == 0 then
      vim.fn.system({ "git", "merge-base", "--is-ancestor", commit, br })
      if vim.v.shell_error == 0 then
        table.insert(candidate_branches, br)
      end
    end
  end

  require("plugins.diffview")

  -- If no branch contains this commit, just show the commit itself
  if #candidate_branches == 0 then
    utils.notify("git_open_commit", commit:sub(1, 8))
    vim.cmd("DiffviewOpen " .. commit .. "^!")
    return
  end

  -- We want the first candidate branch in our ordered list that contains the commit
  local target_branch = candidate_branches[1]

  -- Check if the commit itself is a merge commit
  vim.fn.system({ "git", "rev-parse", "--verify", commit .. "^2" })
  local is_merge = vim.v.shell_error == 0
  if is_merge then
    utils.notify("git_open_merge", string.format("%s (merged in %s)", commit:sub(1, 8), target_branch))
    vim.cmd("DiffviewOpen " .. commit .. "^!")
    return
  end

  -- Check if the commit is in the first-parent history of the target branch
  local first_parent_list = vim.fn.system({ "git", "rev-list", "--first-parent", target_branch })
  local is_first_parent = vim.v.shell_error == 0 and first_parent_list:find(commit, 1, true) ~= nil
  if is_first_parent then
    utils.notify("git_open_commit", string.format("%s (found on %s first-parent)", commit:sub(1, 8), target_branch))
    vim.cmd("DiffviewOpen " .. commit .. "^!")
    return
  end

  -- If not, find the oldest first-parent ancestor of commit H on target_branch (the merge commit)
  local escaped_branch = vim.fn.shellescape(target_branch)
  local find_merge_cmd = string.format(
    "(git rev-list %s..%s --ancestry-path 2>/dev/null | cat -n; git rev-list %s..%s --first-parent 2>/dev/null | cat -n) | sort -k2 -s | uniq -f1 -d | sort -n | tail -1 | cut -f2",
    commit, escaped_branch, commit, escaped_branch
  )
  local merge_commit = vim.trim(vim.fn.system(find_merge_cmd))
  if merge_commit ~= "" then
    utils.notify("git_open_merge", string.format("%s (merged into %s)", merge_commit:sub(1, 8), target_branch))
    vim.cmd("DiffviewOpen " .. merge_commit .. "^!")
    return
  end

  -- Fallback to the commit itself
  utils.notify("git_open_commit", string.format("%s (fallback)", commit:sub(1, 8)))
  vim.cmd("DiffviewOpen " .. commit .. "^!")
end

vim.keymap.set("n", "<leader>gm", open_line_feature_diff, { desc = "View Merge/Feature Diff for Current Line" })

