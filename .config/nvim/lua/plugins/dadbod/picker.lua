-- lua/plugins/dadbod/picker.lua
-- Fuzzy schema searcher and interactive table browser.

local M = {}

--- Fuzzy search and browse database tables using Snacks picker
function M.browse_tables()
  local bufnr  = vim.api.nvim_get_current_buf()
  local db_url = vim.b[bufnr].db or vim.g.db
  if not db_url or db_url == "" then
    require("core.utils").notify("db_no_connection")
    return
  end

  local shared = require("plugins.dadbod.shared")
  shared.fetch_tables_async(db_url, bufnr, function(tables)
    if not tables or #tables == 0 then
      require("core.utils").notify("db_no_tables")
      return
    end

    local items = {}
    for _, t in ipairs(tables) do
      local display_name = (t.schema and t.schema ~= "") and (t.schema .. "." .. t.name) or t.name
      table.insert(items, {
        text = display_name,
        tbl_name = display_name,
      })
    end

    require("snacks").picker({
      title = "Database Tables",
      items = items,
      format = "text",
      preview = function(ctx)
        local tbl = ctx.item.tbl_name
        local p_bufnr = ctx.buf

        -- Store target name to prevent out-of-order async rendering
        vim.b[p_bufnr].preview_target = tbl
        vim.bo[p_bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(p_bufnr, 0, -1, false, { "Loading columns for " .. tbl .. "..." })

        shared.fetch_columns_async(db_url, tbl, p_bufnr, function(columns)
          if not vim.api.nvim_buf_is_valid(p_bufnr) then return end

          if vim.b[p_bufnr].preview_target == tbl then
            vim.bo[p_bufnr].modifiable = true
            if columns then
              local lines = shared.rows_to_display_lines(columns)
              table.insert(lines, 1, "Table: " .. tbl)
              table.insert(lines, 2, string.rep("=", #tbl + 7))
              table.insert(lines, 3, "")
              vim.api.nvim_buf_set_lines(p_bufnr, 0, -1, false, lines)
              vim.bo[p_bufnr].filetype = "sql"
              vim.bo[p_bufnr].modifiable = false
            else
              vim.api.nvim_buf_set_lines(p_bufnr, 0, -1, false, { "Failed to load columns for " .. tbl })
            end
          end
        end)
      end,
      confirm = function(picker, item)
        picker:close()
        if item and item.tbl_name then
          vim.api.nvim_put({ item.tbl_name }, "c", true, true)
        end
      end,
    })
  end)
end

return M
