-- Background process tracking and cancellation by buffer.

local M = {}

---@type table<integer, table<string, table[]>>
local active = {}

--- Track a background job for a buffer.
--- @param bufnr integer
--- @param job table
--- @param scope? string
function M.track(bufnr, job, scope)
  scope = scope or "default"
  active[bufnr] = active[bufnr] or {}
  active[bufnr][scope] = active[bufnr][scope] or {}
  table.insert(active[bufnr][scope], job)
end

--- Stop tracking a completed background job.
--- @param bufnr integer
--- @param job table
--- @param scope? string
function M.untrack(bufnr, job, scope)
  scope = scope or "default"
  local buffer_scopes = active[bufnr]
  local buffer_jobs = buffer_scopes and buffer_scopes[scope]
  if not buffer_jobs then return end
  for index, tracked in ipairs(buffer_jobs) do
    if tracked == job then
      table.remove(buffer_jobs, index)
      break
    end
  end
  if #buffer_jobs == 0 then buffer_scopes[scope] = nil end
  if not next(buffer_scopes) then active[bufnr] = nil end
end

--- Kill all background jobs tracked for a buffer.
--- @param bufnr integer
--- @param scope? string
function M.kill_for_buf(bufnr, scope)
  local buffer_scopes = active[bufnr]
  if not buffer_scopes then return end

  local function kill_scope(scope_name)
    for _, job in ipairs(buffer_scopes[scope_name] or {}) do
      pcall(function() job:kill(9) end)
    end
    buffer_scopes[scope_name] = nil
  end

  if scope then
    kill_scope(scope)
    if not next(buffer_scopes) then active[bufnr] = nil end
  else
    for scope_name in pairs(buffer_scopes) do
      kill_scope(scope_name)
    end
    active[bufnr] = nil
  end
end

function M.kill_all()
  for bufnr in pairs(active) do
    M.kill_for_buf(bufnr)
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = M.kill_all,
})

vim.api.nvim_create_autocmd("BufDelete", {
  callback = function(args)
    M.kill_for_buf(args.buf)
  end,
})

return M
