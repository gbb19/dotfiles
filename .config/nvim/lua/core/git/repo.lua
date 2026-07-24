local M = {}

---Return the current repository root, or nil outside a Git repository.
---@return string|nil
function M.root()
  local root = vim.trim(vim.fn.system({ "git", "rev-parse", "--show-toplevel" }))
  return (vim.v.shell_error == 0 and root ~= "") and root or nil
end

---Return the current branch name, or nil when Git cannot resolve HEAD.
---@return string|nil
function M.current_branch()
  local branch = vim.trim(vim.fn.system({ "git", "rev-parse", "--abbrev-ref", "HEAD" }))
  return (vim.v.shell_error == 0 and branch ~= "") and branch or nil
end

return M
