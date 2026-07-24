local M = {}
local cached_context
local last_tick
local last_cursor

function M.detect_sql_context(bufnr, row, col, line)
  local line_before = line:sub(1, col)
  if line_before:match("[%w_%-\"]+%.[%w_]*$") then return "column" end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, row, false)
  lines[#lines] = line_before
  local text = table.concat(lines, " "):gsub("%-%-[^\n]*", ""):gsub("/%*.-%*/", ""):gsub("%s+", " ")
  local last_keyword
  for word in text:gmatch("[%w_]+") do
    local upper_word = word:upper()
    if upper_word == "FROM" or upper_word == "JOIN" or upper_word == "UPDATE" or upper_word == "INTO" or upper_word == "TABLE" then
      last_keyword = "table"
    elseif upper_word == "SELECT" or upper_word == "WHERE" or upper_word == "SET" or upper_word == "AND" or upper_word == "OR" or upper_word == "ON" or upper_word == "BY" then
      last_keyword = "column"
    end
  end
  return last_keyword or "keyword"
end

function M.get_sql_context_cached()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= "sql" then return "keyword" end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local tick = vim.b[bufnr].changedtick
  if last_tick == tick and last_cursor and last_cursor[1] == cursor[1] and last_cursor[2] == cursor[2] then
    return cached_context
  end

  last_tick = tick
  last_cursor = cursor
  cached_context = M.detect_sql_context(
    bufnr,
    cursor[1],
    cursor[2],
    vim.api.nvim_get_current_line()
  )
  return cached_context
end

function M.setup(blink)
  blink.setup({
    keymap = {
      preset = "default",
      ["<Tab>"] = { "accept", "fallback" },
    },
    sources = {
      default = { "lazydev", "lsp", "path", "snippets", "buffer" },
      per_filetype = {
        sql = { "sql_columns", "sql_tables", "sql_keywords", "snippets", "buffer" },
      },
      providers = {
        lazydev = {
          name = "LazyDev",
          module = "lazydev.integrations.blink",
          score_offset = 100,
        },
        sql_columns = {
          name = "SQL Columns",
          module = "plugins.dadbod.columns",
          score_offset = 200,
          opts = {},
        },
        sql_tables = {
          name = "SQL Tables",
          module = "plugins.dadbod.tables",
          score_offset = 150,
          opts = {},
        },
        sql_keywords = {
          name = "SQL Keywords",
          module = "plugins.dadbod.keywords",
          score_offset = 100,
          opts = {},
        },
        buffer = {
          opts = {
            get_bufnrs = function()
              return vim.tbl_filter(function(bufnr)
                return not vim.api.nvim_buf_get_name(bufnr):match("node_modules")
              end, vim.api.nvim_list_bufs())
            end,
          },
        },
      },
    },
    completion = {
      list = {
        selection = {
          preselect = true,
          auto_insert = false,
        },
      },
      menu = {
        border = "rounded",
        auto_show = false,
        draw = {
          columns = {
            { "kind_icon", "label", gap = 1 },
            { "description" },
          },
          components = {
            label = { width = { fill = true } },
            description = {
              ellipsis = true,
              text = function(ctx) return ctx.item.detail or "" end,
              highlight = "BlinkCmpLabelDetail",
            },
          },
        },
      },
      documentation = { window = { border = "rounded" } },
    },
    signature = { window = { border = "rounded" } },
    fuzzy = {
      sorts = {
        function(a, b)
          local sql_sources = { sql_columns = true, sql_tables = true, sql_keywords = true }
          if not sql_sources[a.source_id] or not sql_sources[b.source_id] then return end

          local context = M.get_sql_context_cached()
          local priorities = context == "column"
              and { sql_columns = 3, sql_keywords = 2, sql_tables = 1 }
            or context == "table"
              and { sql_tables = 3, sql_keywords = 2, sql_columns = 1 }
            or { sql_keywords = 3, sql_columns = 2, sql_tables = 1 }
          local a_priority = priorities[a.source_id] or 0
          local b_priority = priorities[b.source_id] or 0
          if a_priority ~= b_priority then return a_priority > b_priority end

          local a_sort = a.sortText or a.label
          local b_sort = b.sortText or b.label
          if a_sort ~= b_sort then return a_sort < b_sort end
        end,
        "exact",
        "score",
        "sort_text",
        "kind",
        "label",
      },
    },
  })
end

return M
