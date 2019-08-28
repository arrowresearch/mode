--
-- Async primitives on top of Lua coroutine API.
--

local util = require 'mode.util'
local LinkedList = util.LinkedList

-- Coroutine utils
--
-- This code is borrowed from https://github.com/bartbes/co2 and is licensed
-- under BSD-3 license.

local function strip_traceback_header(traceback)
  return traceback:gsub("^.-\n", "")
end

local function traceback(coro, level)
  level = level or 0

  local parts = {}

  if coro then
    table.insert(parts, debug.traceback(coro))
  end

  -- Note: for some reason debug.traceback needs a string to pass a level
  -- But if you pass a string it adds a newline
  table.insert(parts, debug.traceback("", 2 + level):sub(2))

  for i = 2, #parts do
    parts[i] = strip_traceback_header(parts[i])
  end

  return table.concat(parts, "\n\t-- coroutine boundary --\n")
end

local function xpresume(coro, handler, ...)
  local function dispatch(status, maybe_err, ...)
    if status then
      return true, maybe_err, ...
    else
      return false, handler(maybe_err, coro)
    end
  end

  return dispatch(coroutine.resume(coro, ...))
end

local function generic_error_handler(msg, coro)
  msg = string.format(
    "Coroutine failure: %s\n\nCoroutine %s",
    msg,
    traceback(coro)
  )
  error(msg)
end

local function resume(coro, ...)
  return select(2, xpresume(coro, generic_error_handler, ...))
end

-- Channel

local Channel = util.Object:extend()

function Channel:init()
  self.closed = false
  self.listeners = LinkedList.empty
end

function Channel:subscribe(f)
  assert(not self.closed, 'Channel: channel is closed')
  self.listeners = LinkedList.add(self.listeners, f)
  return function()
    self.listeners = LinkedList.remove(self.listeners, f)
  end
end

function Channel:wait_next()
  local running = coroutine.running()
  assert(running, 'Should be called from a coroutine')
  -- luacheck: push ignore unused unsubscribe
  local unsubscribe = self:subscribe(function(value)
    unsubscribe()
    resume(running, value)
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

local Future = util.Object:extend()

Future.none = {}

function Future:init()
  self.value = Future.none
  self.listeners = LinkedList.empty
end

function Future:subscribe(f)
  if self.value ~= Future.none then
    f(self.value)
    return function() end
  else
    self.listeners = LinkedList.add(self.listeners, f)
    return function()
      self.listeners = LinkedList.remove(self.listeners, f)
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
      resume(running, value)
    end)
    return coroutine.yield()
  end
end

function Future:map(f)
  local next = Future:new()
  self:subscribe(function(result)
    next:put(f(result))
  end)
  return next
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

local Task = util.Object:extend()

function Task:init(f)
  self.completed = Future:new()
  self.coro = coroutine.create(function()
    f()
    self.completed:put()
  end)
  resume(self.coro)
end

function Task:wait()
  return self.completed:wait()
end

local function task(f)
  return Task:new(f)
end

return {
  Channel = Channel,
  Future = Future,
  Task = Task,
  task = task,
}
