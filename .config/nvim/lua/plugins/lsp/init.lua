-- LSP entry point: package registration and native server orchestration.
local languages = require("languages")
local utils = require("core.utils")

vim.env.PATH = vim.fn.stdpath("data") .. "/mason/bin:" .. vim.env.PATH

vim.pack.add({
  "https://github.com/neovim/nvim-lspconfig",
  { src = "https://github.com/Saghen/blink.cmp", version = vim.version.range("1") },
  "https://github.com/williamboman/mason.nvim",
  "https://github.com/williamboman/mason-lspconfig.nvim",
  "https://github.com/folke/lazydev.nvim",
})

if vim.bo.filetype == "sql" then pcall(require, "plugins.dadbod") end

local lazydev_ok, lazydev = pcall(require, "lazydev")
if lazydev_ok then
  lazydev.setup({
    library = {
      { path = "${3rd}/luv/library", words = { "vim%.uv" } },
    },
  })
else
  utils.notify("config_completion_failed", "lazydev: " .. tostring(lazydev), { title = "Neovim config" })
end

local blink_ok, blink = pcall(require, "blink.cmp")
if blink_ok then
  require("plugins.lsp.completion").setup(blink)
else
  utils.notify("config_completion_failed", tostring(blink), { title = "Neovim config" })
end

require("plugins.lsp.mason").setup(utils)

local capabilities = blink_ok
    and blink.get_lsp_capabilities()
  or vim.lsp.protocol.make_client_capabilities()

local function get_executable(resolved)
  local cmd = resolved and resolved.cmd
  if type(cmd) == "table" then return cmd[1] end
  if type(cmd) == "string" then return cmd end
end

for _, server in ipairs(languages.lsp_servers) do
  local ok, config = pcall(require, "plugins.lsp.servers." .. server)
  local server_opts = ok and config or {}
  server_opts.capabilities = vim.tbl_deep_extend(
    "force",
    capabilities,
    server_opts.capabilities or {}
  )
  vim.lsp.config(server, server_opts)

  local executable = get_executable(vim.lsp.config[server])
  if executable == nil or vim.fn.executable(executable) == 1 then
    vim.lsp.enable(server)
  end
end

require("plugins.lsp.attach").setup()
require("plugins.lsp.diagnostics").setup(utils)
