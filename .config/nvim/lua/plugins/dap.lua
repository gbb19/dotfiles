-- lua/plugins/dap.lua
-- Configure Debug Adapter Protocol (DAP) for Neovim

-- Add dap, dap-ui, nio, and virtual-text using Neovim's built-in vim.pack
vim.pack.add({
  "https://github.com/mfussenegger/nvim-dap",
  "https://github.com/rcarriga/nvim-dap-ui",
  "https://github.com/nvim-neotest/nvim-nio",
})

local dap_ok, dap = pcall(require, "dap")
local dapui_ok, dapui = pcall(require, "dapui")

if dap_ok and dapui_ok then
  -- Patch nvim-dap to support VS Code preLaunchTask using Overseer
  local overseer_ok, overseer = pcall(require, "overseer")
  if overseer_ok then
    overseer.enable_dap()
  end

  -- Setup DAP UI with a clean dark-mode friendly styling
  dapui.setup({
    controls = {
      element = "repl",
      enabled = true,
      icons = {
        disconnect = "",
        pause = "",
        play = "",
        run_last = "",
        step_back = "",
        step_into = "",
        step_out = "",
        step_over = "",
        terminate = ""
      }
    },
    expand_lines = true,
    floating = {
      border = "rounded",
      mappings = {
        close = { "q", "<Esc>" }
      }
    },
    layouts = {
      {
        elements = {
          { id = "scopes", size = 0.70 },
          { id = "stacks", size = 0.30 }
        },
        position = "left",
        size = 45
      },
      {
        elements = {
          { id = "repl", size = 0.45 },
          { id = "console", size = 0.35 },
          { id = "breakpoints", size = 0.20 }
        },
        position = "bottom",
        size = 10
      }
    }
  })

  -- Automatically open/close DAP UI panels when debugging starts/ends
  dap.listeners.before.attach.dapui_config = function()
    dapui.open()
  end
  dap.listeners.before.launch.dapui_config = function()
    dapui.open()
  end
  dap.listeners.before.event_terminated.dapui_config = function()
    dapui.close()
  end
  dap.listeners.before.event_exited.dapui_config = function()
    dapui.close()
  end

  -- Centralized debug gutter signs (aligned with visual guidelines)
  vim.fn.sign_define("DapBreakpoint", { text = "🔴", texthl = "DiagnosticError", linehl = "", numhl = "" })
  vim.fn.sign_define("DapBreakpointCondition", { text = "🟡", texthl = "DiagnosticWarn", linehl = "", numhl = "" })
  vim.fn.sign_define("DapLogPoint", { text = "💬", texthl = "DiagnosticInfo", linehl = "", numhl = "" })
  vim.fn.sign_define("DapStopped", { text = "▶️", texthl = "DiagnosticOK", linehl = "Visual", numhl = "" })
  vim.fn.sign_define("DapBreakpointRejected", { text = "🚫", texthl = "DiagnosticError", linehl = "", numhl = "" })

  -- Register Node/TypeScript Debug Adapter
  dap.adapters["pwa-node"] = {
    type = "server",
    host = "localhost",
    port = "${port}",
    executable = {
      command = "node",
      args = {
        vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js",
        "${port}",
      },
      options = {
        detached = false,
      },
    }
  }
  -- Alias legacy "node" type to "pwa-node" for launch.json compatibility
  dap.adapters["node"] = dap.adapters["pwa-node"]

  -- Define fallback launch configurations for JS/TS projects (in case .vscode/launch.json doesn't exist)
  local project_core = require("core.project")
  local default_skip_files = { "<node_internals>/**", "**/node_modules/**" }
  local skip_files = project_core.get_dap_skip_files(default_skip_files)
  local smart_step = project_core.get_dap_smart_step(true)

  local js_config = {
    {
      type = "pwa-node",
      request = "launch",
      name = "Launch Current File (pwa-node)",
      program = "${file}",
      cwd = "${workspaceFolder}",
      sourceMaps = true,
      smartStep = smart_step,
      protocol = "inspector",
      console = "integratedTerminal",
      skipFiles = skip_files,
      outFiles = { "${workspaceFolder}/dist/**/*.js", "${workspaceFolder}/build/**/*.js" },
      resolveSourceMapLocations = {
        "${workspaceFolder}/**",
        "!**/node_modules/**",
      },
    },
    {
      type = "pwa-node",
      request = "attach",
      name = "Attach to Port 9229",
      port = 9229,
      cwd = "${workspaceFolder}",
      sourceMaps = true,
      smartStep = smart_step,
      protocol = "inspector",
      skipFiles = skip_files,
      resolveSourceMapLocations = {
        "${workspaceFolder}/**",
        "!**/node_modules/**",
      },
    }
  }

  -- Attach fallback configurations to relevant JavaScript/TypeScript filetypes
  dap.configurations.javascript = js_config
  dap.configurations.typescript = js_config
  dap.configurations.javascriptreact = js_config
  dap.configurations.typescriptreact = js_config

  -- Map VS Code configuration types to Neovim filetypes for on-demand loading
  local vscode_ok, dap_vscode = pcall(require, "dap.ext.vscode")
  if vscode_ok then
    dap_vscode.type_to_filetypes["node"] = { "javascript", "typescript" }
    dap_vscode.type_to_filetypes["pwa-node"] = { "javascript", "typescript", "javascriptreact", "typescriptreact" }
  end

  -- Helper to kill the adapter process by its port (cross-platform: Linux, macOS, Windows)
  local function cleanup_dap_process(session)
    if not session or not session.config then return end
    local adapter = session.adapter
    if adapter and adapter.type == "server" and adapter.port then
      -- Verify if the adapter is configured to spawn an executable locally
      local is_local = false
      local dap_ok, dap_mod = pcall(require, "dap")
      if dap_ok then
        local global_adapter = dap_mod.adapters[session.config.type]
        if type(global_adapter) == "table" and global_adapter.executable then
          is_local = true
        elseif type(global_adapter) == "function" then
          is_local = true
        end
      end

      if is_local then
        local port = tonumber(adapter.port)
        if port then
          if vim.fn.has("win32") == 1 then
            -- Windows implementation using PowerShell
            local cmd = string.format("powershell -Command \"Get-NetTCPConnection -LocalPort %d -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess | ForEach-Object { Stop-Process -Id $_ -Force }\"", port)
            pcall(vim.fn.system, cmd)
          else
            -- Linux & macOS implementation
            if vim.fn.executable("fuser") == 1 then
              pcall(vim.fn.system, string.format("fuser -k -TERM %d/tcp", port))
            elseif vim.fn.executable("lsof") == 1 then
              pcall(vim.fn.system, string.format("lsof -t -i tcp:%d | xargs kill -15 2>/dev/null", port))
            elseif vim.fn.executable("ss") == 1 then
              local out = vim.fn.system(string.format("ss -lptn 'sport = :%d' 2>/dev/null", port))
              local pid = out:match("pid=(%d+)")
              if pid then
                pcall(vim.fn.system, string.format("kill -15 %s 2>/dev/null", pid))
              end
            end
          end
        end
      end
    end
  end

  -- Register listeners to clean up the server process on session end
  dap.listeners.after.event_terminated["dap_cleanup"] = function(session)
    cleanup_dap_process(session)
  end
  dap.listeners.after.event_exited["dap_cleanup"] = function(session)
    cleanup_dap_process(session)
  end

  -- Auto-terminate all debug sessions and processes on Neovim exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("DAPCleanup", { clear = true }),
    callback = function()
      local ok, dap_mod = pcall(require, "dap")
      if ok then
        for _, session in pairs(dap_mod.sessions()) do
          cleanup_dap_process(session)
          dap_mod.terminate(session)
        end
      end
    end,
  })
end
