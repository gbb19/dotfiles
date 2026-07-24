-- Load language registry (auto-discovered from lua/languages/)
local languages = require("languages")
local utils = require("core.utils")

-- Add lspconfig, blink.cmp, and mason using built-in vim.pack
-- Prepend Mason bin to PATH so LSP executables installed via Mason are discoverable
vim.env.PATH = vim.fn.stdpath("data") .. "/mason/bin:" .. vim.env.PATH

vim.pack.add({
  "https://github.com/neovim/nvim-lspconfig",
  -- Pin blink.cmp to stable v1.x series to use prebuilt binaries
  { src = "https://github.com/Saghen/blink.cmp", version = vim.version.range("1") },
  -- Declarative package manager for LSPs
  "https://github.com/williamboman/mason.nvim",
  "https://github.com/williamboman/mason-lspconfig.nvim",
  -- Manage workspace libraries for Neovim config files dynamically
  "https://github.com/folke/lazydev.nvim",
})

-- If the current file is SQL, pre-load plugins.dadbod to ensure the dadbod completion source
-- is in the package path before blink.cmp initializes its providers.
if vim.bo.filetype == "sql" then
  pcall(require, "plugins.dadbod")
end

-- Safely configure plugins
local lazydev_ok, lazydev = pcall(require, "lazydev")
if lazydev_ok then
  lazydev.setup({
    library = {
      -- Load luvit types when the `vim.uv` word is found
      { path = "${3rd}/luv/library", words = { "vim%.uv" } },
    },
  })
end
local blink_ok, blink = pcall(require, "blink.cmp")
local mason_ok, mason = pcall(require, "mason")
local mason_lspconfig_ok, mason_lspconfig = pcall(require, "mason-lspconfig")

-- Helper to dynamically detect SQL query context for smart completion sorting
local function detect_sql_context(bufnr, row, col, line)
  -- 1. Check if cursor is immediately after a dot "." (alias/schema selection)
  local line_before = line:sub(1, col)
  if line_before:match("[%w_%-\"]+%.[%w_]*$") then
    return "column"
  end

  -- 2. Get buffer lines up to current cursor position to parse preceding context
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, row, false)
  lines[#lines] = line_before
  local text = table.concat(lines, " ")

  -- Strip SQL comments to avoid false keyword matches
  text = text:gsub("%-%-[^\n]*", ""):gsub("/%*.-%*/", "")
  text = text:gsub("%s+", " ")

  -- Match the last significant SQL clause keyword before the cursor
  local last_keyword = nil
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

local cached_context = nil
local last_tick = nil
local last_cursor = nil

local function get_sql_context_cached()
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  if ft ~= "sql" then
    return "keyword"
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local tick = vim.b[bufnr].changedtick

  if last_tick == tick and last_cursor and last_cursor[1] == cursor[1] and last_cursor[2] == cursor[2] then
    return cached_context
  end

  last_tick = tick
  last_cursor = cursor

  local row, col = cursor[1], cursor[2]
  local line = vim.api.nvim_get_current_line()

  cached_context = detect_sql_context(bufnr, row, col, line)
  return cached_context
end

-- 1. Setup Autocomplete engine (blink.cmp)
if blink_ok then
  blink.setup({
    keymap = {
      preset = "default",
      ["<Tab>"] = { "accept", "fallback" }, -- Map Tab to accept completion when menu is open
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
        -- Custom SQL column source: resolves schema-qualified aliases and fetches
        -- column names directly from PostgreSQL, bypassing vim-dadbod-completion limitations.
        sql_columns = {
          name = "SQL Columns",
          module = "plugins.dadbod.columns",
          score_offset = 200, -- highest priority in SQL buffers
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
              -- Exclude files in node_modules from being indexed by the buffer completion source
              return vim.tbl_filter(function(bufnr)
                local name = vim.api.nvim_buf_get_name(bufnr)
                return not name:match("node_modules")
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
          auto_insert = false, -- Don't insert text into buffer while navigating with C-n/C-p
        },
      },
      menu = {
        border = "rounded",
        auto_show = false, -- Only show menu when manually triggered (e.g. C-space)
        draw = {
          columns = {
            { "kind_icon", "label", gap = 1 },
            { "description" },
          },
          components = {
            label = {
              width = { fill = true },
            },
            description = {
              ellipsis = true,
              text = function(ctx)
                return ctx.item.detail or ""
              end,
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
        -- Custom sort: dynamically prioritize SQL sources based on syntax context
        function(a, b)
          local sql_sources = { sql_columns = true, sql_tables = true, sql_keywords = true }
          if sql_sources[a.source_id] and sql_sources[b.source_id] then
            local ctx_type = get_sql_context_cached()
            local priorities
            if ctx_type == "column" then
              priorities = { sql_columns = 3, sql_keywords = 2, sql_tables = 1 }
            elseif ctx_type == "table" then
              priorities = { sql_tables = 3, sql_keywords = 2, sql_columns = 1 }
            else -- "keyword"
              priorities = { sql_keywords = 3, sql_columns = 2, sql_tables = 1 }
            end

            local a_prio = priorities[a.source_id] or 0
            local b_prio = priorities[b.source_id] or 0
            if a_prio ~= b_prio then
              return a_prio > b_prio
            end

            local a_sort = a.sortText or a.label
            local b_sort = b.sortText or b.label
            if a_sort ~= b_sort then
              return a_sort < b_sort
            end
          end
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

-- 2. Setup LSP installer (mason & mason-lspconfig)
if mason_ok then
  mason.setup({
    ui = { border = "rounded" },
  })

  -- Hook Mason registry events to show installing progress notifications using Snacks
  local registry_ok, registry = pcall(require, "mason-registry")
  if registry_ok then
    registry:on("package:install:start", function(pkg)
      pcall(function()
        utils.notify("mason_installing", pkg.name)
      end)
    end)

    registry:on("package:install:success", function(pkg)
      pcall(function()
        utils.notify("mason_installed", pkg.name)
      end)
    end)

    registry:on("package:install:failed", function(pkg)
      pcall(function()
        utils.notify("mason_install_failed", pkg.name)
      end)
    end)
  end
end

if mason_lspconfig_ok then
  mason_lspconfig.setup({
    -- Do not install automatically on startup. Use :LspInstallAll to trigger manually.
    ensure_installed = {},
    automatic_enable = false,
  })
end

-- 3. Configure LSP servers via native Neovim 0.12+ APIs
local capabilities = blink_ok and blink.get_lsp_capabilities() or vim.lsp.protocol.make_client_capabilities()

local function get_executable(resolved)
  local cmd = resolved and resolved.cmd
  if type(cmd) == "table" then
    return cmd[1]
  elseif type(cmd) == "string" then
    return cmd
  end
  return nil
end

for _, server in ipairs(languages.lsp_servers) do
  -- Load custom overrides from the plugins/lsp/servers/ directory
  local ok, config = pcall(require, "plugins.lsp.servers." .. server)
  local server_opts = ok and config or {}

  -- Merge capabilities
  server_opts.capabilities = vim.tbl_deep_extend("force", capabilities, server_opts.capabilities or {})

  vim.lsp.config(server, server_opts)

  -- Only enable the server if its executable is available to prevent annoying "Spawning language server failed" errors
  local resolved = vim.lsp.config[server]
  local executable = get_executable(resolved)

  if executable == nil or vim.fn.executable(executable) == 1 then
    vim.lsp.enable(server)
  end
end

-- LSP Keymaps setup using LspAttach autocmd (SOLID - Loose Coupling)
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", {}),
  callback = function(ev)
    local opts = { buffer = ev.buf }
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if not client then
      return
    end

    -- Automatically disable formatting for LSP clients if conform has a formatter configured
    -- for the buffer's filetype. This prevents double-formatting conflicts.
    local conform_ok, conform = pcall(require, "conform")
    if conform_ok then
      local formatters = conform.list_formatters(ev.buf)
      local has_available_formatter = false
      for _, f in ipairs(formatters or {}) do
        if f.available then
          has_available_formatter = true
          break
        end
      end
      if has_available_formatter then
        client.server_capabilities.documentFormattingProvider = false
        client.server_capabilities.documentRangeFormattingProvider = false
      end
    end

    -- 1. Enable inlay hints by default (toggle with <leader>ci)
    vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })

    -- 2. Apply global LSP keymaps
    if client.name ~= "graphql" then
      vim.keymap.set("n", "gd", function()
        Snacks.picker.lsp_definitions()
      end, vim.tbl_extend("force", opts, { desc = "Go to Definition" }))
    end
    vim.keymap.set("n", "gy", function()
      vim.lsp.buf.type_definition({
        on_list = function(options)
          local items = options.items
          local has_custom = false

          if #items > 1 then
            local filtered = {}
            for _, item in ipairs(items) do
              local filename = item.filename
              if filename and not filename:match("node_modules") and not filename:match("lib%..*%.d%.ts") then
                table.insert(filtered, item)
              end
            end
            if #filtered > 0 then
              items = filtered
              has_custom = true
            end
          else
            local filename = items[1] and items[1].filename
            if filename and not filename:match("node_modules") and not filename:match("lib%..*%.d%.ts") then
              has_custom = true
            end
          end

          if #items == 1 then
            local item = items[1]
            require("core.layout").jump_to_normal_window()
            vim.cmd("normal! m'")
            vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
            vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
          elseif #items > 1 then
            if not has_custom then
              -- Fallback: jump to the first library definition directly if no custom types exist
              local item = items[1]
              require("core.layout").jump_to_normal_window()
              vim.cmd("normal! m'")
              vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
              vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
            else
              -- Open picker for multiple custom definitions
              vim.fn.setqflist({}, " ", { title = options.title, items = items, context = options.context })
              vim.schedule(function()
                Snacks.picker.qflist()
              end)
            end
          end
        end,
      })
    end, vim.tbl_extend("force", opts, { desc = "Go to Type Definition" }))
    if client.name ~= "graphql" then
      vim.keymap.set("n", "gr", function()
        Snacks.picker.lsp_references()
      end, vim.tbl_extend("force", opts, { desc = "Go to References" }))
    end
    vim.keymap.set("n", "gi", function()
      Snacks.picker.lsp_implementations()
    end, vim.tbl_extend("force", opts, { desc = "Go to Implementation" }))
    local ft = vim.bo[ev.buf].filetype
    if client.name ~= "graphql" and ft ~= "sql" and ft ~= "dbout" then
      vim.keymap.set("n", "K", function()
        vim.lsp.buf.hover({ border = "rounded" })
      end, vim.tbl_extend("force", opts, { desc = "Hover Documentation" }))
    end
    vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "Rename Symbol" }))
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "Code Action" }))
    vim.keymap.set("n", "<leader>ci", function()
      local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
      vim.lsp.inlay_hint.enable(not enabled, { bufnr = 0 })
    end, vim.tbl_extend("force", opts, { desc = "Toggle Inlay Hints" }))
    vim.keymap.set(
      "n",
      "<leader>cs",
      "<cmd>lsp restart<CR>",
      vim.tbl_extend("force", opts, { desc = "Restart LSP Server" })
    )

    -- 3. Apply server-specific configuration/keymaps (like vtsls TS/JS refactoring keys)
    local ok, server_config = pcall(require, "plugins.lsp.servers." .. client.name)
    if ok and server_config.on_attach then
      server_config.on_attach(client, ev.buf)
    end
  end,
})

-- Diagnostic navigation keymaps (Global)
vim.keymap.set("n", "[d", function()
  vim.diagnostic.jump({ count = -1 })
end, { desc = "Go to Previous Diagnostic" })

vim.keymap.set("n", "]d", function()
  vim.diagnostic.jump({ count = 1 })
end, { desc = "Go to Next Diagnostic" })

vim.keymap.set("n", "[e", function()
  vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR })
end, { desc = "Go to Previous Error" })

vim.keymap.set("n", "]e", function()
  vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR })
end, { desc = "Go to Next Error" })

-- Copy diagnostic under cursor to system clipboard
vim.keymap.set("n", "<leader>cy", function()
  local line_diags = vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })
  if #line_diags == 0 then
    utils.notify("diagnostic_missing")
    return
  end

  local messages = {}
  for _, diag in ipairs(line_diags) do
    table.insert(messages, string.format("[%s] %s", diag.source or "LSP", diag.message))
  end
  local full_text = table.concat(messages, "\n")

  vim.fn.setreg("+", full_text)
  utils.notify("diagnostic_copied", line_diags[1].message)
end, { desc = "Copy / Yank Diagnostic Message" })
