local M = {}

local base_branches = {
  "dev",
  "develop",
  "origin/dev",
  "origin/develop",
  "master",
  "main",
  "origin/master",
  "origin/main",
  "staging",
  "origin/staging",
  "HEAD",
}

local function succeeds(command)
  vim.fn.system(command)
  return vim.v.shell_error == 0
end

function M.resolve_line_commit(file, line)
  local blame = vim.fn.system({
    "git",
    "blame",
    "-L",
    string.format("%d,%d", line, line),
    "--porcelain",
    file,
  })
  if vim.v.shell_error ~= 0 or blame == "" then return nil, "git_blame_failed" end

  local commit = blame:match("^(%x+)")
  if not commit or commit:match("^0+$") then return nil, "git_uncommitted" end

  local candidates = {}
  for _, branch in ipairs(base_branches) do
    if succeeds({ "git", "rev-parse", "--verify", branch })
      and succeeds({ "git", "merge-base", "--is-ancestor", commit, branch })
    then
      candidates[#candidates + 1] = branch
    end
  end

  if #candidates == 0 then
    return { commit = commit, kind = "commit", detail = commit:sub(1, 8) }
  end

  local target = candidates[1]
  if succeeds({ "git", "rev-parse", "--verify", commit .. "^2" }) then
    return {
      commit = commit,
      kind = "merge",
      detail = string.format("%s (merged in %s)", commit:sub(1, 8), target),
    }
  end

  local first_parent = vim.fn.system({ "git", "rev-list", "--first-parent", target })
  if vim.v.shell_error == 0 and first_parent:find(commit, 1, true) then
    return {
      commit = commit,
      kind = "commit",
      detail = string.format("%s (found on %s first-parent)", commit:sub(1, 8), target),
    }
  end

  local branch = vim.fn.shellescape(target)
  local command = string.format(
    "(git rev-list %s..%s --ancestry-path 2>/dev/null | cat -n; git rev-list %s..%s --first-parent 2>/dev/null | cat -n) | sort -k2 -s | uniq -f1 -d | sort -n | tail -1 | cut -f2",
    commit,
    branch,
    commit,
    branch
  )
  local merge_commit = vim.trim(vim.fn.system(command))
  if merge_commit ~= "" then
    return {
      commit = merge_commit,
      kind = "merge",
      detail = string.format("%s (merged into %s)", merge_commit:sub(1, 8), target),
    }
  end

  return {
    commit = commit,
    kind = "commit",
    detail = string.format("%s (fallback)", commit:sub(1, 8)),
  }
end

return M
