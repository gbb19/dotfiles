local utils = require("core.utils")

vim.api.nvim_create_user_command("LoadEnv", function(opts)
  local filename = opts.args ~= "" and opts.args or ".env"
  local file = io.open(filename, "r")
  if not file then
    utils.notify("load_env_not_found", filename)
    return
  end

  for line in file:lines() do
    if not line:match("^%s*#") and line:match("=") then
      local key, value = line:match("^%s*([^=%s]+)%s*=%s*(.-)%s*$")
      if key and value then
        local quote = value:match("^([\"'])")
        if quote then
          value = value:match("^" .. quote .. "(.-)" .. quote) or value
        else
          value = value:match("^([^#]-)%s*$") or value
        end
        vim.env[key] = value
      end
    end
  end

  file:close()
  utils.notify("load_env_success", filename)
end, {
  nargs = "?",
  complete = "file",
  desc = "Load environment variables from a .env file into vim.env",
})
