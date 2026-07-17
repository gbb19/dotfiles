-- lua/languages/rust.lua
-- Language config for Rust.
-- LSP server overrides live in lua/plugins/lsp/servers/rust_analyzer.lua

---@type LanguageConfig
return {
  lsp = {
    servers = { "rust_analyzer" },
    mason   = { "rust-analyzer" }, -- Mason package name uses hyphen
  },
  formatters = {
    -- rustfmt ships with the Rust toolchain (rustup); run via system PATH, not Mason
    rust = { "rustfmt" },
  },
}
