-- Background process tracking and cancellation by buffer.

local M = {}

---@type table<integer, table[]>
local active = {}

--- Track a background job for a buffer.
--- @param bufnr integer
--- @param job table
function M.track(bufnr, job)
  active[bufnr] = active[bufnr] or {}
  table.insert(active[bufnr], job)
end

--- Stop tracking a completed background job.
--- @param bufnr integer
--- @param job table
function M.untrack(bufnr, job)
  local buffer_jobs = active[bufnr]
  if not buffer_jobs then return end
  for index, tracked in ipairs(buffer_jobs) do
    if tracked == job then
      table.remove(buffer_jobs, index)
      break
    end
  end
  if #buffer_jobs == 0 then active[bufnr] = nil end
end

--- Kill all background jobs tracked for a buffer.
--- @param bufnr integer
function M.kill_for_buf(bufnr)
  local buffer_jobs = active[bufnr]
  if not buffer_jobs then return end
  for _, job in ipairs(buffer_jobs) do
    pcall(function() job:kill(9) end)
  end
  active[bufnr] = nil
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
