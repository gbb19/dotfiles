local M = {}

M.settings = {
  Lua = {
    runtime = {
      version = "LuaJIT",
    },
    diagnostics = {
      globals = { "vim" },
    },
    workspace = {
      -- Make the server aware of Neovim runtime files
      library = vim.api.nvim_get_runtime_file("", true),
      checkThirdParty = false,
    },
    telemetry = {
      enable = false,
    },
    hint = {
      enable = true, -- Enable inlay hints for Lua
    },
  },
}

return M
