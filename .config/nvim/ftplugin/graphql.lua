-- ftplugin/graphql.lua
-- Custom Go-to-Definition (gd) and Find-References (gr) fallbacks for GraphQL files.
-- Since graphql-lsp has limited support for navigation between SDL schema files,
-- we use fast regex/grep search under Snacks picker for 100% reliable navigation.

local bufnr = vim.api.nvim_get_current_buf()
local opts = { buffer = bufnr, silent = true }

-- 1. Go to definition (gd) -> search for type/input/enum declaration of the word
vim.keymap.set("n", "gd", function()
  local cword = vim.fn.expand("<cword>")
  if cword == "" then return end

  local pattern = "^(type|input|enum|interface|scalar|union)\\s+" .. cword .. "\\b"
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    snacks.picker.grep({
      search = pattern,
      glob = "*.graphql",
      title = "GraphQL Definition: " .. cword,
    })
  else
    vim.cmd("silent! grep! " .. vim.fn.shellescape(pattern) .. " --include=*.graphql")
    vim.cmd("copen")
  end
end, vim.tbl_extend("force", opts, { desc = "Go to GraphQL Definition" }))

-- 2. Find references (gr) -> search for all occurrences of the word in .graphql files
vim.keymap.set("n", "gr", function()
  local cword = vim.fn.expand("<cword>")
  if cword == "" then return end

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    snacks.picker.grep({
      search = cword,
      args = { "-w" },
      glob = "*.graphql",
      title = "GraphQL References: " .. cword,
    })
  else
    vim.cmd("silent! grep! -w " .. vim.fn.shellescape(cword) .. " --include=*.graphql")
    vim.cmd("copen")
  end
end, vim.tbl_extend("force", opts, { desc = "Find GraphQL References" }))

-- 3. Custom Hover (K) -> search for definition and display its block in a floating window
vim.keymap.set("n", "K", function()
  local cword = vim.fn.expand("<cword>")
  if cword == "" then return end

  local cmd = string.format("rg --vimgrep -w '^(type|input|enum|interface|scalar|union)\\s+%s\\b' -g '*.graphql'", cword)
  local results = vim.fn.systemlist(cmd)
  if #results == 0 then
    vim.lsp.buf.hover({ border = "rounded" })
    return
  end

  -- Parse the first result (Linux format filename:line:col:content)
  local parts = vim.split(results[1], ":")
  local filename = parts[1]
  local start_line = tonumber(parts[2])
  if not filename or not start_line then
    vim.lsp.buf.hover({ border = "rounded" })
    return
  end

  -- Read the block from the file
  local f = io.open(filename, "r")
  if not f then
    vim.lsp.buf.hover({ border = "rounded" })
    return
  end

  local lines = {}
  local line_num = 1
  local in_block = false
  local brace_count = 0
  for line in f:lines() do
    if line_num >= start_line then
      table.insert(lines, line)
      
      local _, opens = line:gsub("{", "")
      local _, closes = line:gsub("}", "")
      brace_count = brace_count + opens - closes
      
      if line:find("{") then
        in_block = true
      end
      
      if in_block and brace_count <= 0 then
        break
      end
      if #lines >= 50 then
        break
      end
    end
    line_num = line_num + 1
  end
  f:close()

  if #lines > 0 then
    -- Open floating preview window containing the extracted GraphQL code
    vim.lsp.util.open_floating_preview(lines, "graphql", { border = "rounded" })
  else
    vim.lsp.buf.hover({ border = "rounded" })
  end
end, vim.tbl_extend("force", opts, { desc = "GraphQL Hover Definition" }))
