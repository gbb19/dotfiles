-- Set leader keys (must be set before any keymaps/plugins are loaded)
vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- Line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Tabs & Indentation
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Search settings
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true

-- Split windows
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Scroll margins (keep space at top/bottom/sides when scrolling)
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

-- Performance & System
vim.opt.termguicolors = true
vim.opt.clipboard = "unnamedplus"

-- Use OSC 52 clipboard integration in remote containers or SSH where xclip/wl-copy might not work.
-- This sends escape sequences to the host terminal, which then copies the text to the host system clipboard.
if vim.fn.has("nvim-0.10.0") == 1 then
  local osc52_ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  if osc52_ok then
    vim.g.clipboard = {
      name = "OSC 52",
      copy = {
        ["+"] = osc52.copy("+"),
        ["*"] = osc52.copy("*"),
      },
      paste = {
        ["+"] = osc52.paste("+"),
        ["*"] = osc52.paste("*"),
      },
    }
  end
end

vim.opt.mouse = "a"
vim.opt.updatetime = 250
vim.opt.signcolumn = "yes"
vim.opt.timeoutlen = 300
vim.opt.cursorline = true  -- Highlight the current line
vim.opt.pumheight = 10     -- Limit completion menu to 10 items max
vim.opt.exrc = true    -- Enable project-local config (.nvim.lua)
vim.opt.undofile = true -- Persist undo history across sessions (stored in ~/.local/state/nvim/undo/)
vim.opt.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"
vim.opt.autoread = true -- Automatically reload files changed on disk
vim.opt.spell     = true
vim.opt.spelllang = { "en" }


-- Disable legacy system providers (increases startup speed and cleans checkhealth)
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0


