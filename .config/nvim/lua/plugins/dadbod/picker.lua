-- lua/plugins/dadbod/picker.lua
-- Fuzzy schema searcher and interactive table browser.

local M = {}

local function is_internal_table(schema, name)
  local s = (schema or ""):lower()
  local n = (name or ""):lower()

  -- Filter system & internal schemas
  if s:find("pg_catalog") or s:find("information_schema") or s:find("pgagent") or s:find("timescale") or s:find("^_%w+") then
    return true
  end

  -- Filter system & internal tables (Timescale chunks, columnstore, sqlite internal, pg internal)
  if n:find("^_timescaledb") or n:find("columnstore") or n:find("compressed") or n:find("^sqlite_") or n:find("^pg_") then
    return true
  end

  return false
end

--- Fuzzy search and browse database tables using Snacks picker.
--- @param opts? { view_only?: boolean }
function M.browse_tables(opts)
  opts = opts or {}
  local is_view_only = opts.view_only ~= false -- Default to View-Only inspection unless explicitly false

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
      if not is_internal_table(t.schema, t.name) then
        local display_name = (t.schema and t.schema ~= "") and (t.schema .. "." .. t.name) or t.name
        table.insert(items, {
          text = display_name,
          tbl_name = display_name,
          schema = t.schema,
          name = t.name,
        })
      end
    end

    if #items == 0 then
      require("core.utils").notify("db_no_tables")
      return
    end

    require("snacks").picker({
      title = is_view_only and "Inspect DB Schema & Tables (View Only)" or "Database Tables",
      items = items,
      format = function(item, picker)
        local ret = {}
        if item.schema and item.schema ~= "" and item.schema ~= "public" and item.schema ~= "main" then
          table.insert(ret, { item.schema .. ".", "SnacksPickerGitBranch" })
          table.insert(ret, { item.name, "Normal" })
        else
          table.insert(ret, { item.tbl_name, "Normal" })
        end
        return ret
      end,
      preview = function(ctx)
        local tbl = ctx.item.tbl_name
        local p_bufnr = ctx.buf

        -- Store target name to prevent out-of-order async rendering
        vim.b[p_bufnr].preview_target = tbl
        vim.bo[p_bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(p_bufnr, 0, -1, false, { "-- Loading columns for " .. tbl .. "..." })

        shared.fetch_columns_async(db_url, tbl, p_bufnr, function(columns)
          if not vim.api.nvim_buf_is_valid(p_bufnr) then return end

          if vim.b[p_bufnr].preview_target == tbl then
            vim.bo[p_bufnr].modifiable = true
            if columns then
              local lines = shared.rows_to_display_lines(columns)
              table.insert(lines, 1, "-- Table Schema: " .. tbl)
              table.insert(lines, 2, "-- " .. string.rep("=", #tbl + 15))
              table.insert(lines, 3, "")
              vim.api.nvim_buf_set_lines(p_bufnr, 0, -1, false, lines)
              vim.bo[p_bufnr].filetype = "sql"
              vim.bo[p_bufnr].modifiable = false
            else
              vim.api.nvim_buf_set_lines(p_bufnr, 0, -1, false, { "-- Failed to load columns for " .. tbl })
            end
          end
        end)
      end,
      confirm = function(picker, item)
        picker:close()
        if item and item.tbl_name then
          if is_view_only then
            local query = string.format("SELECT * FROM %s LIMIT 50;", item.tbl_name)
            vim.schedule(function()
              pcall(vim.cmd, "DB " .. query)
              vim.defer_fn(function()
                pcall(function()
                  require("plugins.dadbod.init").open_last_result()
                end)
              end, 200)
            end)
          else
            vim.api.nvim_put({ item.tbl_name }, "c", true, true)
          end
        end
      end,
    })
  end)
end

--- View-only inspection mode (shortcut)
function M.inspect_tables()
  M.browse_tables({ view_only = true })
end

return M
