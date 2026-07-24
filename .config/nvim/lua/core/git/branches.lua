local M = {}

---@class CoreGitBranch
---@field text string
---@field branch string
---@field commit string
---@field is_remote boolean
---@field cwd string|nil
---@field current boolean
---@field ahead integer|nil
---@field behind integer|nil
---@field gone boolean|nil

---Parse `git branch -vv` output without changing its input order.
---@param lines string[]
---@param root string|nil
---@return CoreGitBranch[]
function M.parse_local(lines, root)
  local items = {}
  for _, line in ipairs(lines) do
    if line ~= "" and not line:find("HEAD%s*%->") then
      local status, branch = line:match("^(.)%s+(%S+)")
      if branch then
        local status_str = line:match("%[%S+:%s*([^%]]+)%]")
        local ahead = status_str and status_str:match("ahead%s+(%d+)")
        local behind = status_str and status_str:match("behind%s+(%d+)")
        local gone = status_str == "gone"

        items[#items + 1] = {
          text = branch,
          branch = branch,
          commit = branch,
          is_remote = false,
          cwd = root,
          current = status == "*",
          ahead = ahead and tonumber(ahead) or nil,
          behind = behind and tonumber(behind) or nil,
          gone = gone,
        }
      end
    end
  end
  return items
end

---Parse `git branch -r` output without changing its input order.
---@param lines string[]
---@param root string|nil
---@return CoreGitBranch[]
function M.parse_remote(lines, root)
  local items = {}
  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" and not trimmed:find("HEAD%s*%->") then
      items[#items + 1] = {
        text = trimmed,
        branch = trimmed,
        commit = trimmed,
        is_remote = true,
        cwd = root,
        current = false,
      }
    end
  end
  return items
end

---List local branches followed by remote branches in Git's committer-date order.
---@param root string|nil
---@return CoreGitBranch[]
function M.list(root)
  local items = {}
  local local_out = vim.fn.systemlist({
    "git",
    "-c",
    "core.quotepath=false",
    "branch",
    "--no-color",
    "-vv",
    "--sort=-committerdate",
  })
  if vim.v.shell_error == 0 then
    vim.list_extend(items, M.parse_local(local_out, root))
  end

  local remote_out = vim.fn.systemlist({
    "git",
    "-c",
    "core.quotepath=false",
    "branch",
    "--no-color",
    "-r",
    "--sort=-committerdate",
  })
  if vim.v.shell_error == 0 then
    vim.list_extend(items, M.parse_remote(remote_out, root))
  end

  return items
end

return M
