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
