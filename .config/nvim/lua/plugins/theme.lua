-- Add onedark theme using built-in vim.pack
vim.pack.add({
  "https://github.com/navarasu/onedark.nvim",
})

-- Centralized color palette for the default onedark theme
local onedark_colors = {
  bg0 = "#20242A",        -- Editor background
  bg1 = "#262A31",        -- Floating windows & Panel background
  bg_d = "#20242A",       -- Statusline & Terminal background
  bg2 = "#2B303A",        -- Cursor line background
  bg_select = "#2c384e",  -- Selected item background (dark slate blue)
  bg_search = "#473c29",  -- Inactive search highlight background (dark gold)
  hint    = "#7A8FA8",   -- Hint fg: distinctly blue-toned, darker than regular text (#ABB2BF)
  bg_hint = "#2A303A",    -- Hint bg: slightly lighter than bg1 for subtle distinction

  -- Syntax colors: matched to Zed One Dark (muted vs stock onedark)
  red    = "#D07277",     -- property, variable.parameter  (stock: #E06C75)
  orange = "#BF956A",     -- number, boolean, string.regex  (stock: #D19A66)
  yellow = "#DFC184",     -- constant, selector             (stock: #E5C07B)
  green  = "#A1C181",     -- string, text.literal           (stock: #98C379)
  cyan   = "#6EB4BF",     -- type, enum, operator           (stock: #56B6C2)
  blue   = "#74ADE8",     -- function, constructor, label   (stock: #61AFEF)
  purple = "#B477CF",     -- keyword, preproc               (stock: #C678DD)
}

local onedark_highlights = {
  -- 1. Floating Windows
  NormalFloat = { bg = onedark_colors.bg1 },
  FloatBorder = { fg = onedark_colors.hint, bg = onedark_colors.bg1 },

  -- 2. Underlines for Diagnostics (Curly error lens underlines)
  DiagnosticUnderlineError = { fmt = "undercurl", sp = "$red" },
  DiagnosticUnderlineWarn  = { fmt = "undercurl", sp = "$orange" },
  DiagnosticUnderlineInfo  = { fmt = "undercurl", sp = "$blue" },
  DiagnosticUnderlineHint  = { fmt = "undercurl", sp = "$grey" },

  -- 3. Snacks Indent Lines
  SnacksIndent = { fg = "#353b45" },
  SnacksIndentScope = { fg = "#5c6370" },

  -- 4. Snacks Picker
  SnacksPickerListCursorLine = { bg = onedark_colors.bg_select, fg = "#ffffff", bold = true },
  SnacksPickerMatch = { fg = "$blue", bold = true },
  SnacksPickerSearch = { bg = onedark_colors.bg_search, fg = "$yellow", bold = true },
  SnacksPickerPreviewCursorLine = { bg = onedark_colors.bg2 },
  SnacksPickerGitCommit = { fg = "$yellow" },
  SnacksPickerGitDate = { fg = "$purple" },
  SnacksPickerGitAuthor = { fg = "$green" },
  SnacksPickerGitBranch = { fg = "$cyan" },
  SnacksPickerGitBranchCurrent = { fg = "$blue", bold = true },
  SnacksPickerGitStatusAdded = { fg = "$green" },
  SnacksPickerGitStatusModified = { fg = "$orange" },
  SnacksPickerGitStatusDeleted = { fg = "$red" },

  -- 5. Lualine custom components
  LualineGitBlame = { fg = "#5c6370" },

  -- 6. LSP Inlay Hints
  LspInlayHint = { fg = onedark_colors.hint, bg = onedark_colors.bg_hint },

  -- 7. Native Buffer Search (/ and ?)
  Search = { bg = onedark_colors.bg_search, fg = "$yellow", bold = true },
  CurSearch = { bg = "$yellow", fg = onedark_colors.bg0, bold = true },
  IncSearch = { bg = "$yellow", fg = onedark_colors.bg0, bold = true },

  -- 8. Treesitter Context (barely-there: bg1 is just slightly lighter than editor bg0)
  TreesitterContext           = { bg = onedark_colors.bg1 },
  TreesitterContextLineNumber = { bg = onedark_colors.bg1, fg = "#3B4048" },
  TreesitterContextBottom     = { underline = true, sp = "#3B4048" },
  TreesitterContextSeparator  = { fg = "#3B4048" },
}

-- Load onedark with configuration
local ok, onedark = pcall(require, "onedark")
if not ok then return end

onedark.setup({
  style = "dark",
  transparent = false,
  term_colors = true,
  colors = onedark_colors,
  highlights = onedark_highlights,
})

vim.cmd("colorscheme onedark")
