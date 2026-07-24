-- Git branch picker UI.

local M = {}
local preview_timer = nil

--- Register the Git branch picker mapping.
--- @param opts { ensure_unfixed_window: function }
function M.setup(opts)
  local function open_branches(picker_opts)
    opts.ensure_unfixed_window()
    picker_opts = picker_opts or {}
    local git_branches = require("core.git.branches")

    Snacks.picker(vim.tbl_deep_extend("force", {
      source = "git_branches",
      title = "Git Branches",
      finder = function(_, ctx)
        local root = ctx:git_root()
        return ctx.filter:filter(git_branches.list(root))
      end,
      format = function(item)
        local align = Snacks.picker.util.align
        local formatted = {}
        if item.current then
          table.insert(formatted, { align("* ", 2), "SnacksPickerGitBranchCurrent" })
        else
          table.insert(formatted, { align("  ", 2) })
        end
        table.insert(formatted, { item.branch, "SnacksPickerGitBranch" })

        if not item.is_remote then
          local status = {}
          if item.ahead then
            table.insert(status, { "↑" .. item.ahead, "SnacksPickerGitAhead" })
          end
          if item.behind then
            if #status > 0 then table.insert(status, { " " }) end
            table.insert(status, { "↓" .. item.behind, "SnacksPickerGitBehind" })
          end
          if item.gone then
            table.insert(status, { "[gone]", "SnacksPickerGitGone" })
          end
          if #status > 0 then
            table.insert(formatted, { " " })
            vim.list_extend(formatted, status)
          end
        end
        return formatted
      end,
      preview = function(ctx)
        if not ctx.item or not ctx.item.branch then return end
        ctx.preview:set_title("Branch: " .. ctx.item.branch)
        if preview_timer then
          pcall(vim.uv.timer_stop, preview_timer)
          preview_timer = nil
        end
        preview_timer = vim.defer_fn(function()
          if ctx.picker and not ctx.picker.closed and ctx.buf and vim.api.nvim_buf_is_valid(ctx.buf) then
            local cmd = {
              "git", "-c", "core.quotepath=false", "--no-pager",
              "log", "-n", "15", "--stat", ctx.item.branch,
            }
            pcall(require("snacks.picker.preview").cmd, cmd, ctx, { ft = "git" })
          end
        end, 80)
      end,
    }, picker_opts))
  end

  vim.keymap.set("n", "<leader>gc", function()
    open_branches()
  end, { desc = "Git Checkout Branch (Local First + MRU)" })
end

return M
