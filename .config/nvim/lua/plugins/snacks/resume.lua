local M = {}

M.state = {}

---Capture the state needed to resume a picker without rerunning its finder.
---@param source string
---@param picker snacks.Picker
function M.capture(source, picker)
  local items = (picker.finder and picker.finder.items) or (picker.list and picker.list.items)
  M.state[source] = {
    opts = picker.init_opts or {},
    selected = picker:selected({ fallback = false }),
    cursor = picker.list.cursor,
    topline = picker.list.top,
    filter = picker.input.filter,
    items = items and #items > 0 and items or nil,
  }
end

---Open a picker and capture its state when it closes.
---@param source string
---@param open fun(opts: table): snacks.Picker
---@param opts? table
---@return snacks.Picker
function M.open(source, open, opts)
  opts = opts or {}
  local on_close = opts.on_close
  opts.on_close = function(picker)
    if on_close then
      on_close(picker)
    end
    M.capture(source, picker)
  end
  return open(opts)
end

---@param source string
---@return boolean
function M.has(source)
  return M.state[source] ~= nil
end

---Resume a captured picker with its cached items and viewport.
---@param source string
---@return snacks.Picker|nil
function M.resume(source)
  local state = M.state[source]
  if not state then
    return nil
  end

  state.opts.pattern = state.filter.pattern
  state.opts.search = state.filter.search
  if state.items then
    state.opts.finder = function()
      return state.items
    end
  end

  local picker = Snacks.picker.pick(state.opts)
  if state.cursor and picker and picker.list then
    picker.list.target = { cursor = state.cursor, top = state.topline or 1 }
    picker.list.cursor = state.cursor
    if state.topline then
      picker.list.top = state.topline
    end
    pcall(function()
      picker.list:view(state.cursor, state.topline)
    end)
  end

  picker.list:set_selected(state.selected)
  picker.list:update()
  picker.input:update()
  picker.matcher.task:on(
    "done",
    vim.schedule_wrap(function()
      if picker.closed then
        return
      end
      if state.cursor then
        picker.list:view(state.cursor, state.topline)
        picker.list.target = nil
      end
    end)
  )
  return picker
end

return M
