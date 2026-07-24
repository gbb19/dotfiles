local files = vim.fn.glob("lua/plugins/dadbod/**/*.lua", false, true)
local graph = {}

for _, path in ipairs(files) do
  local module = path
    :gsub("^lua/", "")
    :gsub("%.lua$", "")
    :gsub("/", ".")
  graph[module] = graph[module] or {}

  local lines = vim.fn.readfile(path)
  local content = table.concat(lines, "\n")
  for dependency in content:gmatch('require%s*%(%s*["\'](plugins%.dadbod%.[^"\']+)["\']%s*%)') do
    graph[module][dependency] = true
  end
end

local visiting = {}
local visited = {}
local stack = {}

local function visit(module)
  if visiting[module] then
    local cycle = {}
    local in_cycle = false
    for _, entry in ipairs(stack) do
      if entry == module then
        in_cycle = true
      end
      if in_cycle then
        cycle[#cycle + 1] = entry
      end
    end
    cycle[#cycle + 1] = module
    return table.concat(cycle, " -> ")
  end
  if visited[module] then
    return nil
  end

  visiting[module] = true
  stack[#stack + 1] = module
  for dependency in pairs(graph[module] or {}) do
    if graph[dependency] then
      local cycle = visit(dependency)
      if cycle then
        return cycle
      end
    end
  end
  stack[#stack] = nil
  visiting[module] = nil
  visited[module] = true
  return nil
end

for module in pairs(graph) do
  local cycle = visit(module)
  if cycle then
    io.stderr:write("Dadbod module cycle detected: " .. cycle .. "\n")
    vim.cmd("cquit 1")
  end
end

print(("Dadbod dependency check passed: %d modules"):format(vim.tbl_count(graph)))
