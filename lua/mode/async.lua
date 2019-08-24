--
-- Async primitives on top of Lua coroutine API.
--

local util = require 'mode.util'
local LinkedList = util.LinkedList

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
      assert(coroutine.resume(running, value))
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

return {
  Channel = Channel,
  Future = Future,
}
