-- Pinned-first, MRU-sorted buffer picker.

local M = {}

local function is_pinned(bufnr)
  local ok, groups = pcall(require, "bufferline.groups")
  if ok and groups and type(groups._is_pinned) == "function" and groups._is_pinned({ id = bufnr }) then return true end
  local configured = vim.g.BufferlinePinnedBuffers
  if type(configured) == "string" and configured ~= "" then
    local path = vim.api.nvim_buf_get_name(bufnr)
    for _, pinned in ipairs(vim.split(configured, ",")) do
      if pinned == path or pinned == tostring(bufnr) then return true end
    end
  end
  return false
end

local function quick_confirm(view)
  return function(picker)
    picker.list:view(view)
    picker:action("confirm")
  end
end

function M.setup(ensure_unfixed_window)
  vim.keymap.set("n", "<leader>fb", function()
    ensure_unfixed_window()
    Snacks.picker({
      source = "buffers",
      title = "Buffers",
      finder = function(_, ctx)
        local current, alternate = vim.api.nvim_get_current_buf(), vim.fn.bufnr("#")
        local items = {}
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted and vim.bo[bufnr].filetype ~= "dbout" then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name == "" then name = "[Scratch]" end
            local info = vim.fn.getbufinfo(bufnr)[1] or {}
            local mark = vim.api.nvim_buf_get_mark(bufnr, '"')
            local flags = {
              bufnr == current and "%" or (bufnr == alternate and "#" or ""),
              info.hidden == 1 and "h" or (#(info.windows or {}) > 0) and "a" or "",
              vim.bo[bufnr].readonly and "=" or "",
              info.changed == 1 and "+" or "",
            }
            items[#items + 1] = {
              buf = bufnr, name = name, file = name, is_pinned = is_pinned(bufnr), info = info,
              lastused = info.lastused or 0, flags = table.concat(flags), buftype = vim.bo[bufnr].buftype,
              filetype = vim.bo[bufnr].filetype, pos = mark[1] ~= 0 and mark or { info.lnum or 1, 0 },
            }
            items[#items].text = Snacks.picker.util.text(items[#items], { "buf", "name", "filetype", "buftype" })
          end
        end
        table.sort(items, function(a, b)
          if a.is_pinned ~= b.is_pinned then return a.is_pinned end
          return (a.lastused or 0) > (b.lastused or 0)
        end)
        return ctx.filter:filter(items)
      end,
      format = function(item, picker)
        local ret = { { item.is_pinned and "[P] " or "    ", "SnacksPickerLabel" } }
        vim.list_extend(ret, Snacks.picker.format.filename(item, picker))
        return ret
      end,
      win = { input = { keys = {
        ["<A-1>"] = { quick_confirm(1), mode = { "i", "n" } },
        ["<A-2>"] = { quick_confirm(2), mode = { "i", "n" } },
        ["<A-3>"] = { quick_confirm(3), mode = { "i", "n" } },
        ["<A-4>"] = { quick_confirm(4), mode = { "i", "n" } },
        ["<A-5>"] = { quick_confirm(5), mode = { "i", "n" } },
        ["<A-6>"] = { quick_confirm(6), mode = { "i", "n" } },
        ["<A-7>"] = { quick_confirm(7), mode = { "i", "n" } },
        ["<A-8>"] = { quick_confirm(8), mode = { "i", "n" } },
        ["<A-9>"] = { quick_confirm(9), mode = { "i", "n" } },
        ["1"] = { quick_confirm(1), mode = "n" }, ["2"] = { quick_confirm(2), mode = "n" },
        ["3"] = { quick_confirm(3), mode = "n" }, ["4"] = { quick_confirm(4), mode = "n" },
        ["5"] = { quick_confirm(5), mode = "n" }, ["6"] = { quick_confirm(6), mode = "n" },
        ["7"] = { quick_confirm(7), mode = "n" }, ["8"] = { quick_confirm(8), mode = "n" },
        ["9"] = { quick_confirm(9), mode = "n" },
      } } },
    })
  end, { desc = "Find Buffers (Pinned First + MRU)" })
end

return M
