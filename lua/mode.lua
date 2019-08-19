-- luacheck: globals vim

local uv = vim.loop

-- Object
--
-- Simplistic object system for Lua.

local Object = {}
Object.__index = Object

function Object:new(o)
  local instance = {}
  setmetatable(instance, self)
  instance:init(o)
  return instance
end

function Object:extend()
  local cls = self:new()
  cls.__index = cls
  return cls
end

function Object.init(_) end

-- Mutable Linked List

local linked_list_empty = nil

local function linked_list_add(list, value)
  return {value = value, next = list}
end

local function linked_list_remove(list, value)
  local prev = nil
  local current = list

  while current do
    if current.value == value then
      if prev then
        prev.next = current.next
        current.next = nil
        -- We've mutated some intermediate mode in-place, return same head.
        return list
      else
        -- Found element is the previous head, return new head.
        return current.next
      end
      break
    end
    prev = current
    current = current.next
  end
  -- Element wasn't found, return list as-is.
  return list
end

-- Channel

local Channel = Object:extend()

function Channel:init()
  self.closed = false
  self.listeners = linked_list_empty
end

function Channel:subscribe(f)
  assert(not self.closed, 'Channel: channel is closed')
  self.listeners = linked_list_add(self.listeners, f)
  return function()
    self.listeners = linked_list_remove(self.listeners, f)
  end
end

function Channel:wait_next()
  local running = coroutine.running()
  assert(running, 'Should be called from a coroutine')
  -- luacheck: push ignore unused unsubscribe
  local unsubscribe = self:subscribe(function(value)
    unsubscribe()
    assert(coroutine.resume(running, value))
  end)
  -- luacheck: pop
end

function Channel:put(value)
  assert(not self.closed, 'Channel: channel is closed')
  local listeners = self.listeners
  while listeners do
    listeners.value(value)
    listeners = listeners.next
  end
end

function Channel:close()
  self.closed = true
  self.listeners = nil
end

-- Future
--
-- Future is a container for values which will be computed in the future. It can
-- be used as a synchronisation primitive.

local Future = Object:extend()

Future.none = {}

function Future:init()
  self.value = Future.none
  self.listeners = linked_list_empty
end

function Future:subscribe(f)
  if self.value ~= Future.none then
    f(self.value)
    return function() end
  else
    self.listeners = linked_list_add(self.listeners, f)
    return function()
      self.listeners = linked_list_remove(self.listeners, f)
    end
  end
end

function Future:put(value)
  assert(self.value == Future.none, 'Future: already resolved')
  self.value = value
  while self.listeners do
    self.listeners.value(value)
    self.listeners = self.listeners.next
  end
end

function Future:wait()
  if self.value ~= Future.none then
    return self.value
  else
    local running = coroutine.running()
    assert(running, 'Should be called from a coroutine')
    self:subscribe(function(value)
      assert(coroutine.resume(running, value))
    end)
    return coroutine.yield()
  end
end

-- Pipe

local Pipe = Object:extend()

function Pipe:init()
  self.closed = false
  self.handle = uv.new_pipe(false)
end

function Pipe:start_read(f)
  assert(not self.closed, 'Pipe is closed')
  uv.read_start(self.handle, function(err, chunk)
    if err then
      assert(not err, err)
    elseif chunk then
      f(chunk)
    else
      f(nil)
    end
  end)
  return function()
    uv.read_stop(self.handle)
  end
end

function Pipe:read_all()
  assert(not self.closed, 'Pipe is closed')
  local data = Future:new()
  local chunks = {}
  self:start_read(function(chunk)
    if chunk then
      table.insert(chunks, chunk)
    else
      data:put(table.concat(chunks, ""))
    end
  end)
  return data
end

function Pipe:close()
  if not uv.is_closing(self.handle) then
    self.closed = true
    uv.close(self.handle)
  end
end

-- Process
--
-- This is an abstraction on top of libuv process management.

local Process = Object:extend()

function Process:init(o)
  self.cmd = o.cmd
  self.cwd = o.cwd or nil
  self.args = o.args
  self.pid = nil
  self.handle = nil
  self.exit_code = Future:new()
  self.stdin = Pipe:new()
  self.stdout = Pipe:new()
  self.stderr = Pipe:new()
  self:spawn()
end

function Process:spawn()
  local handle, pid = uv.spawn(self.cmd, {
    cwd = self.cwd,
    stdio = { self.stdin.handle, self.stdout.handle, self.stderr.handle },
    args = self.args,
  }, function(exit_code, _)
    self:close()
    self.exit_code:put(exit_code)
  end)
  self.handle = handle
  self.pid = pid
end

function Process:close()
  if self.handle then
    if not uv.is_closing(self.handle) then
      uv.close(self.handle)
    end
    self.stdin:close()
    self.stdout:close()
    self.stderr:close()
  end
end

function Process:kill(signal)
  if self.handle and not uv.is_closing(self.handle) then
    uv.process_kill(self.handle, signal or 'sigterm')
  end
end

-- Task
--
-- This is a wrapper around Lua coroutine which provides conveniences.
--
-- To create a task one does:
--
--   local task = Task:new(function() ... end)
--
-- Then we can wait for its completion:
--
--   task.completed:wait()
--
-- Or we can subscribe to its completion:
--
--   task.completed:subscribe(function() ... end)
--

local Task = Object:extend()

function Task:init(f)
  self.completed = Future:new()
  self.coro = coroutine.create(function()
    f()
    self.completed:put()
  end)
  assert(coroutine.resume(self.coro))
end

function Task:wait()
  return self.completed:wait()
end

-- Vim API

-- Wait for VIM API to be available.
local function wait_vim()
  if not vim.in_fast_event() then
    return
  end
  local running = coroutine.running()
  assert(running, 'Should be called from a coroutine')
  vim.schedule(function()
    assert(coroutine.resume(running))
  end)
  coroutine.yield()
end

-- Test

local function show(o)
  wait_vim()
  print(vim.inspect(o))
end

Task:new(function()
  local proc = Process:new({cmd = '/bin/ls'})
  local out = proc.stdout:read_all():wait()
  local exit_code = proc.exit_code:wait()
  show(out)
  show(exit_code)
end).completed:subscribe(function()
  vim.api.nvim_command('echo "nonsense"')
end)
