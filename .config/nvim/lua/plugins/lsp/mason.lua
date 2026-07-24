local M = {}

function M.setup(utils)
  local mason_ok, mason = pcall(require, "mason")
  if mason_ok then
    mason.setup({ ui = { border = "rounded" } })
    local registry_ok, registry = pcall(require, "mason-registry")
    if registry_ok then
      registry:on("package:install:start", function(pkg) pcall(utils.notify, "mason_installing", pkg.name) end)
      registry:on("package:install:success", function(pkg) pcall(utils.notify, "mason_installed", pkg.name) end)
      registry:on("package:install:failed", function(pkg) pcall(utils.notify, "mason_install_failed", pkg.name) end)
    end
  else
    vim.notify("Mason failed to load: " .. tostring(mason), vim.log.levels.ERROR, { title = "Neovim config" })
  end

  local mason_lspconfig_ok, mason_lspconfig = pcall(require, "mason-lspconfig")
  if mason_lspconfig_ok then
    mason_lspconfig.setup({ ensure_installed = {}, automatic_enable = false })
  else
    vim.notify("mason-lspconfig failed to load: " .. tostring(mason_lspconfig), vim.log.levels.ERROR, { title = "Neovim config" })
  end
end

return M
