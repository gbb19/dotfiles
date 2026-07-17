-- lua/plugins/lsp/servers/rust_analyzer.lua
-- Server-specific config for rust-analyzer.
-- Declared here only; enabled/registered via lua/languages/rust.lua

local M = {}

M.settings = {
  ["rust-analyzer"] = {
    cargo = {
      allFeatures = true,
      loadOutDirsFromCheck = true,
      runBuildScripts = true,
    },
    check = {
      -- Modern config key for clippy on save
      command = "clippy",
      extraArgs = { "--", "-W", "clippy::pedantic" },
    },
    procMacro = {
      enable = true,
      ignored = {
        ["async-trait"] = { "async_trait" },
        ["napi-derive"]  = { "napi" },
        ["async-recursion"] = { "async_recursion" },
      },
    },
    inlayHints = {
      bindingModeHints         = { enable = true },
      chainingHints            = { enable = true },
      closingBraceHints        = { enable = true, minLines = 25 },
      closureReturnTypeHints   = { enable = "always" },
      lifetimeElisionHints     = { enable = "skip_trivial", useParameterNames = true },
      maxLength                = 25, -- expected usize directly
      parameterHints           = { enable = true },
      reborrowHints            = { enable = "mutable" }, -- expected mutable, always, or never
      renderColons             = true, -- expected boolean directly
      typeHints                = { enable = true, hideClosureInitialization = false, hideNamedConstructor = false },
    },
  },
}

return M
