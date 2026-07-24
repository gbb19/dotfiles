-- Add diffview.nvim using built-in vim.pack
vim.pack.add({ "https://github.com/sindrets/diffview.nvim" })

local diffview_ok, diffview = pcall(require, "diffview")
if diffview_ok then
  local utils = require("core.utils")
  local actions = require("diffview.actions")

  -- Global session state for viewed files in PR/code reviews
  _G.diffview_viewed_files = _G.diffview_viewed_files or {}

  local ns = vim.api.nvim_create_namespace("diffview_viewed_files")

  local is_updating = false

  local function update_viewed_extmarks()
    if is_updating then return end
    is_updating = true

    local lib_ok, lib = pcall(require, "diffview.lib")
    if not lib_ok then
      is_updating = false
      return
    end
    local view = lib.get_current_view()
    if not view or not view.panel or not view.panel:buf_loaded() then
      is_updating = false
      return
    end
    local panel = view.panel
    local buf = panel.bufid

    -- Ensure buffer change listener is attached to update extmarks on panel redraw
    if not vim.b[buf].diffview_attached then
      vim.b[buf].diffview_attached = true
      vim.api.nvim_buf_attach(buf, false, {
        on_lines = function()
          vim.schedule(function()
            pcall(update_viewed_extmarks)
          end)
        end
      })
    end

    -- Clear existing marks
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

    if not panel.components then
      is_updating = false
      return
    end

    local comp_lists = {}
    if panel.components.conflicting and panel.components.conflicting.files then
      table.insert(comp_lists, panel.components.conflicting.files)
    end
    if panel.components.working and panel.components.working.files then
      table.insert(comp_lists, panel.components.working.files)
    end
    if panel.components.staged and panel.components.staged.files then
      table.insert(comp_lists, panel.components.staged.files)
    end

    if panel.listing_style == "list" then
      for _, file_list in ipairs(comp_lists) do
        for _, comp_struct in ipairs(file_list) do
          local f = comp_struct.comp.context
          if f and _G.diffview_viewed_files[f.absolute_path] then
            pcall(vim.api.nvim_buf_set_extmark, buf, ns, comp_struct.comp.lstart, 0, {
              virt_text = { { "✓ ", "DiagnosticOk" } },
              virt_text_pos = "inline",
            })
          end
        end
      end
    else
      for _, comp_struct in ipairs(comp_lists) do
        if comp_struct.comp then
          comp_struct.comp:deep_some(function(cur)
            local f = cur.context
            if f and _G.diffview_viewed_files[f.absolute_path] then
              pcall(vim.api.nvim_buf_set_extmark, buf, ns, cur.lstart, 0, {
                virt_text = { { "✓ ", "DiagnosticOk" } },
                virt_text_pos = "inline",
              })
            end
            return false
          end)
        end
      end
    end

    is_updating = false
  end

  local function toggle_viewed()
    local lib_ok, lib = pcall(require, "diffview.lib")
    if not lib_ok then return end
    local view = lib.get_current_view()
    if not view then return end

    local file = view:infer_cur_file()
    if not file then return end

    local path = file.absolute_path
    _G.diffview_viewed_files[path] = not _G.diffview_viewed_files[path]

    update_viewed_extmarks()

    local basename = vim.fs.basename(path)
    if _G.diffview_viewed_files[path] then
      utils.notify("diffview_reviewed", basename)
      -- Auto cycle to the next file
      actions.select_next_entry()
    else
      utils.notify("diffview_unreviewed", basename)
    end
  end

  local function show_file_name()
    local lib_ok, lib = pcall(require, "diffview.lib")
    if not lib_ok then return end

    local view = lib.get_current_view()
    if not view or not view.panel or not view.panel:is_focused() then return end

    local item = view.panel:get_item_at_cursor()
    local name = item and (item.basename or (item.path and vim.fs.basename(item.path)))
    if not name or name == "" then return end

    vim.lsp.util.open_floating_preview({ name }, "text", {
      border = "rounded",
      close_events = { "CursorMoved", "CursorMovedI", "BufHidden", "InsertCharPre" },
      focusable = false,
      title = " File Name ",
      wrap = true,
    })
  end

  local function copy_file_path()
    local lib_ok, lib = pcall(require, "diffview.lib")
    if not lib_ok then return end

    local view = lib.get_current_view()
    if not view or not view.panel or not view.panel:is_focused() then return end

    local item = view.panel:get_item_at_cursor()
    if not item or not item.absolute_path then return end

    local repo_root = item.adapter and item.adapter.ctx and item.adapter.ctx.toplevel
    require("core.files").copy_relative_path(item.absolute_path, repo_root)
  end

  diffview.setup({
    enhanced_diff_hl = true,

    view = {
      default = {
        disable_diagnostics = false,
      },
      merge_tool = {
        disable_diagnostics = false,
      },
    },

    keymaps = {
      -- File panel (left side): navigate with j/k, enter with l/<CR>, jump with gf
      file_panel = {
        { "n", "K", show_file_name, { desc = "Show full file name" } },
        { "n", "<leader>yp", copy_file_path, { desc = "Copy relative file path" } },
        { "n", "gf", function()
          local ok, err = pcall(function()
            actions.select_entry()   -- enter the file (same as l/<CR>): shows diff + updates state
            actions.goto_file_edit() -- open in the pre-diffview editing window
          end)
          if not ok and err then
            utils.notify("diffview_action_failed", err:gsub("^Vim%b():", ""):gsub("^ ", ""))
          end
        end, { desc = "Enter file and open for editing" } },
        { "n", "<C-d>", actions.scroll_view(0.25), { desc = "Scroll the diff view down" } },
        { "n", "<C-u>", actions.scroll_view(-0.25), { desc = "Scroll the diff view up" } },
        { "n", "v", toggle_viewed, { desc = "Toggle file reviewed status" } },
      },
      -- Diff buffers: open file in the pre-diffview editing window
      view = {
        { "n", "gf", function()
          local ok, err = pcall(actions.goto_file_edit)
          if not ok and err then
            utils.notify("diffview_action_failed", err:gsub("^Vim%b():", ""):gsub("^ ", ""))
          end
        end, { desc = "Open file for editing (pre-diffview window)" } },
        { "n", "<leader>v", toggle_viewed, { desc = "Toggle file reviewed status" } },
      },
      -- File history panel
      file_history_panel = {
        { "n", "gf", function()
          local ok, err = pcall(actions.goto_file_edit)
          if not ok and err then
            utils.notify("diffview_action_failed", err:gsub("^Vim%b():", ""):gsub("^ ", ""))
          end
        end, { desc = "Open file for editing" } },
        { "n", "<C-d>", actions.scroll_view(0.25), { desc = "Scroll the diff view down" } },
        { "n", "<C-u>", actions.scroll_view(-0.25), { desc = "Scroll the diff view up" } },
      },
    },

    hooks = {
      diff_buf_read = function()
        -- Disable folding so full file content is always visible
        vim.opt_local.foldenable = false
      end,
    },
  })

  -- Smart quit: when :q would leave only diffview tab(s), close diffview first so
  -- :q exits Neovim naturally without switching to the diffview tab.
  local _smart_quit_active = false
  vim.api.nvim_create_autocmd("QuitPre", {
    desc = "Close diffview when :q would leave only diffview tabs",
    callback = function()
      if _smart_quit_active then return end

      local tabpages = vim.api.nvim_list_tabpages()
      if #tabpages <= 1 then return end

      -- Skip when quitting from inside a diffview window
      local cur_tabpage = vim.api.nvim_get_current_tabpage()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(cur_tabpage)) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype:match("^Diffview") then
          return
        end
      end

      -- Check if every other tab is diffview-only
      for _, tabpage in ipairs(tabpages) do
        if tabpage == cur_tabpage then goto continue end
        local tab_is_diffview = false
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
          if vim.bo[vim.api.nvim_win_get_buf(win)].filetype:match("^Diffview") then
            tab_is_diffview = true
            break
          end
        end
        if not tab_is_diffview then return end
        ::continue::
      end

      -- Force-close all windows in every diffview tab without switching to them.
      -- DiffviewClose causes a flash because it navigates to the tab internally.
      -- nvim_win_close(win, true) closes windows in any tab without changing focus.
      _smart_quit_active = true
      for _, tabpage in ipairs(tabpages) do
        if tabpage == cur_tabpage then goto close_continue end
        local is_diffview_tab = false
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
          if vim.bo[vim.api.nvim_win_get_buf(win)].filetype:match("^Diffview") then
            is_diffview_tab = true
            break
          end
        end
        if is_diffview_tab then
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
            pcall(vim.api.nvim_win_close, win, true)
          end
        end
        ::close_continue::
      end
      _smart_quit_active = false
    end,
  })

  -- Hook redraws on Diffview layout updates
  vim.api.nvim_create_autocmd("User", {
    pattern = "DiffviewViewPostLayout",
    callback = function()
      pcall(update_viewed_extmarks)
    end,
  })

  -- Reset viewed files state on Diffview close
  vim.api.nvim_create_autocmd("User", {
    pattern = "DiffviewViewClosed",
    callback = function()
      _G.diffview_viewed_files = {}
    end,
  })
end
