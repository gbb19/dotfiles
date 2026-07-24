local root = vim.fs.joinpath(vim.fn.stdpath("config"), "lua")
local graph = {}

for _, path in ipairs(vim.fn.globpath(root, "**/*.lua", false, true)) do
  local relative = path:sub(#root + 2):gsub("%.lua$", ""):gsub("/", ".")
  local module = relative:gsub("%.init$", "")
  graph[module] = graph[module] or {}

  local file = assert(io.open(path, "r"))
  local source = file:read("*a")
  file:close()
  for dependency in source:gmatch("require%s*%(%s*[\"']([^\"']+)[\"']%s*%)") do
    graph[module][dependency] = true
  end
end

local visiting = {}
local visited = {}
local stack = {}
local cycles = {}

local function visit(module)
  if visiting[module] then
    local cycle = {}
    local collecting = false
    for _, name in ipairs(stack) do
      if name == module then collecting = true end
      if collecting then cycle[#cycle + 1] = name end
    end
    cycle[#cycle + 1] = module
    cycles[#cycles + 1] = table.concat(cycle, " -> ")
    return
  end
  if visited[module] or not graph[module] then return end

  visiting[module] = true
  stack[#stack + 1] = module
  for dependency in pairs(graph[module]) do visit(dependency) end
  stack[#stack] = nil
  visiting[module] = nil
  visited[module] = true
end

for module in pairs(graph) do visit(module) end

if #cycles > 0 then
  io.stderr:write("Lua module dependency cycles detected:\n- " .. table.concat(cycles, "\n- ") .. "\n")
  vim.cmd("cquit 1")
end

print(("Lua module cycle check passed: %d modules"):format(vim.tbl_count(graph)))
