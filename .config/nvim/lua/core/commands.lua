-- lua/core/commands.lua
-- Global user commands for config maintenance

vim.api.nvim_create_user_command("PackUpdate", function()
  vim.pack.update()
end, { desc = "Update all plugins (shows confirmation buffer)" })

vim.api.nvim_create_user_command("PackUpdateForce", function()
  vim.pack.update(nil, { force = true })
end, { desc = "Force update all plugins without confirmation" })

vim.api.nvim_create_user_command("PackCheck", function()
  vim.pack.update(nil, { offline = true })
end, { desc = "Show plugin status without downloading" })

vim.api.nvim_create_user_command("PackRevert", function()
  vim.pack.update(nil, { target = "lockfile" })
end, { desc = "Revert all plugins to lockfile state" })

vim.api.nvim_create_user_command("PackHealth", function()
  vim.cmd("checkhealth vim.pack")
end, { desc = "Run vim.pack health check" })

vim.api.nvim_create_user_command("PackClean", function()
  local utils = require("core.utils")

  -- Scan config directory for all declared plugins in lua files
  local declared = {}
  local files = vim.fn.glob(vim.fn.stdpath("config") .. "/**/*.lua", false, true)
  for _, file in ipairs(files) do
    local f = io.open(file, "r")
    if f then
      local content = f:read("*a")
      f:close()
      for pack_add_block in content:gmatch("pack%.add%s*(%b())") do
        for url in pack_add_block:gmatch('["\'](https://[^"\']+)["\']') do
          local name = url:match("([^/]+)$"):gsub("%.git$", "")
          if name then
            declared[name] = true
          end
        end
        for name in pack_add_block:gmatch('name%s*=%s*["\']([%w%-_%.]+)["\']') do
          declared[name] = true
        end
      end
    end
  end

  local installed = vim.pack.get()
  local to_delete = {}
  for _, plug in ipairs(installed) do
    local name = plug.spec.name
    if not declared[name] then
      table.insert(to_delete, name)
    end
  end

  if #to_delete == 0 then
    utils.notify("pack_clean_no_unused")
    return
  end

  print("Found unused plugins on disk: " .. table.concat(to_delete, ", "))
  local choice = vim.fn.input("Delete these plugins? (y/N): ")
  if choice:lower() == "y" then
    local delete_ok, err = pcall(vim.pack.del, to_delete)
    if delete_ok then
      utils.notify("pack_clean_success", table.concat(to_delete, ", "))
    else
      utils.notify("pack_clean_failed", tostring(err))
    end
  else
    utils.notify("pack_clean_cancelled")
  end
end, { desc = "Clean all unused plugins from disk and lockfile" })

vim.api.nvim_create_user_command("PackLspInstall", function(opts)
  -- Make sure plugins.lsp is loaded so Mason and mason-lspconfig are initialized
  require("plugins.lsp")

  local utils = require("core.utils")
  local mason_lspconfig_ok, mason_lspconfig = pcall(require, "mason-lspconfig")
  if not mason_lspconfig_ok then
    utils.notify("mason_install_failed", "mason-lspconfig not found")
    return
  end

  local servers = {}
  local daps = {}
  local target = opts.args

  if target and target ~= "" then
    -- Load specific language module
    local ok, config = pcall(require, "languages." .. target)
    if not ok or type(config) ~= "table" then
      utils.notify("language_load_failed", target)
      return
    end
    if config.lsp and config.lsp.mason then
      servers = config.lsp.mason
    end
    if config.dap and config.dap.mason then
      daps = config.dap.mason
    end
  else
    -- Load all configured servers and DAPs
    local languages = require("languages")
    servers = languages.mason_servers
    daps = languages.dap_servers or {}
  end

  if (#servers == 0) and (#daps == 0) then
    utils.notify("lsp_install_no_servers")
    return
  end

  -- Get currently installed LSP servers
  local installed_lsp_set = {}
  for _, s in ipairs(mason_lspconfig.get_installed_servers()) do
    installed_lsp_set[s] = true
  end

  local to_install_lsp = {}
  for _, server in ipairs(servers) do
    if not installed_lsp_set[server] then
      table.insert(to_install_lsp, server)
    end
  end

  -- Get currently installed DAP packages
  local to_install_dap = {}
  local registry_ok, registry = pcall(require, "mason-registry")
  if registry_ok then
    for _, dap_pkg in ipairs(daps) do
      local ok, pkg = pcall(registry.get_package, dap_pkg)
      if ok and not pkg:is_installed() then
        table.insert(to_install_dap, dap_pkg)
      end
    end
  end

  if #to_install_lsp == 0 and #to_install_dap == 0 then
    utils.notify("lsp_install_all_already", string.format("(%d/%d)", #servers + #daps, #servers + #daps))
    return
  end

  -- Install LSP servers
  if #to_install_lsp > 0 then
    utils.notify("lsp_install_starting", table.concat(to_install_lsp, ", "))
    vim.cmd("LspInstall " .. table.concat(to_install_lsp, " "))
  end

  -- Install DAP packages
  if #to_install_dap > 0 then
    utils.notify("dap_install_starting", table.concat(to_install_dap, ", "))
    vim.cmd("MasonInstall " .. table.concat(to_install_dap, " "))
  end
end, {
  nargs = "?",
  complete = function(arg_lead, cmd_line, cursor_pos)
    local lang_dir = vim.fn.stdpath("config") .. "/lua/languages"
    local files = vim.fn.glob(lang_dir .. "/*.lua", false, true)
    local langs = {}
    for _, filepath in ipairs(files) do
      local name = vim.fn.fnamemodify(filepath, ":t:r")
      if name ~= "init" and name:find("^" .. vim.pesc(arg_lead)) then
        table.insert(langs, name)
      end
    end
    return langs
  end,
  desc = "Install configured LSP and DAP servers (optional: specify language)"
})

-- Highlight on yank (flash effect when copying text)
vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("HighlightYank", { clear = true }),
  callback = function()
    vim.highlight.on_yank({
      higroup = "IncSearch",
      timeout = 150,
    })
  end,
})

-- Automatically check and reload files changed on disk externally
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  group = vim.api.nvim_create_augroup("AutoReloadFiles", { clear = true }),
  callback = function()
    if vim.o.buftype == "" then
      vim.cmd("checktime")
    end
  end,
})

-- Automatically refresh TypeScript projects when focus is regained
vim.api.nvim_create_autocmd("FocusGained", {
  group = vim.api.nvim_create_augroup("LspAutoRefresh", { clear = true }),
  callback = function()
    for _, client in ipairs(vim.lsp.get_clients()) do
      if client.name == "vtsls" then
        client:request("workspace/executeCommand", {
          command = "_typescript.reloadProjects",
        }, nil, 0)
      end
    end
  end,
})
