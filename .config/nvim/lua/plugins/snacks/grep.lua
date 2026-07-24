-- Stateful grep picker filters and resume workflow.

local M = {}

local last_include = nil
local last_exclude = nil
local last_search = ""
local reset_pending = false

local function build_args(include, exclude)
  local args = {}
  for _, pattern in ipairs(vim.split(include or "", "[,%s]+", { trimempty = true })) do
    vim.list_extend(args, { "--glob", pattern })
  end
  for _, pattern in ipairs(vim.split(exclude or "", "[,%s]+", { trimempty = true })) do
    vim.list_extend(args, { "--glob", "!" .. pattern })
  end
  return args
end

local function reset_filters()
  last_include = nil
  last_exclude = nil
  last_search = ""
end

--- Register the stateful grep picker mappings.
--- @param opts { ensure_unfixed_window: function, picker_resume: table }
function M.setup(opts)
  local function open_grep(include, exclude, search)
    opts.ensure_unfixed_window()
    local args = build_args(include, exclude)
    reset_pending = false

    opts.picker_resume.open("grep", Snacks.picker.grep, {
      args = #args > 0 and args or nil,
      search = search,
      win = {
        input = {
          keys = {
            ["<C-c>"] = { "grep_force_reset", mode = { "i", "n" } },
          },
        },
      },
      actions = {
        grep_force_reset = function(picker)
          reset_pending = true
          picker:close()
        end,
      },
      on_close = function(picker)
        local query = picker.input.filter.search
        if reset_pending or not query or vim.trim(query) == "" then
          reset_filters()
          return
        end
        last_search = query
      end,
    })
  end

  vim.keymap.set("n", "<leader>fg", function()
    opts.ensure_unfixed_window()
    local has_resume_state = opts.picker_resume.has("grep")
    local force_filter_prompts = reset_pending

    if vim.v.count == 0 and has_resume_state and not force_filter_prompts then
      opts.picker_resume.resume("grep")
      return
    end

    vim.ui.input({
      prompt = "  Grep include (glob, Esc=skip): ",
      default = last_include or "",
    }, function(include)
      if include == nil then
        if has_resume_state and not force_filter_prompts then
          opts.picker_resume.resume("grep")
        else
          open_grep(last_include or "", last_exclude or "", last_search)
        end
        return
      end
      last_include = include

      vim.ui.input({
        prompt = "  Grep exclude (glob, Esc=skip): ",
        default = last_exclude or "",
      }, function(exclude)
        exclude = exclude or (last_exclude or "")
        last_exclude = exclude
        open_grep(last_include, exclude, last_search)
      end)
    end)
  end, { desc = "Live Grep (Resume; [count]=edit filters)" })

  vim.keymap.set("n", "<leader>fG", function()
    opts.ensure_unfixed_window()
    reset_filters()
    opts.picker_resume.open("grep", Snacks.picker.grep)
  end, { desc = "Live Grep (Fresh Search)" })
end

return M
