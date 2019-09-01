-- luacheck: globals vim
--
-- High-level wrapper for libuv API.
--

local uv = vim.loop
local util = require 'mode.util'
local path = require 'mode.path'
local async = require 'mode.async'

-- Timer

local function sleep(delay)
  local resp = async.Future:new()
  local timer = uv.new_timer()
  uv.timer_start(timer, delay, 0, function ()
    uv.timer_stop(timer)
    uv.close(timer)
    resp:put()
  end)
  return resp
end

-- Stream

local Stream = util.Object:extend()

function Stream:init()
  self.is_shutdown = false
end

function Stream:write(data)
  local status = async.Future:new()
  uv.write(self.handle, data, function(err)
    status:put(err)
  end)
  return status
end

function Stream:read_start(f)
  assert(self.handle, 'Stream.read_start: no handle')
  local handle = self.handle
  uv.read_start(handle, function(err, chunk)
    if err then
      assert(not err, err)
    elseif chunk then
      f(chunk)
    else
      f(nil)
    end
  end)
  return function()
    uv.read_stop(handle)
  end
end

function Stream:read_all()
  assert(self.handle, 'Stream.read_all: no handle')
  local data = async.Future:new()
  local chunks = {}
  self:read_start(function(chunk)
    if chunk then
      table.insert(chunks, chunk)
    else
      data:put(table.concat(chunks, ""))
    end
  end)
  return data
end

function Stream:close()
  if not self.handle then
    return
  end
  uv.close(self.handle)
  self.handle = nil
end

function Stream:shutdown()
  local resp = async.Future:new()
  if self.handle and not self.is_shutdown then
    self.is_shutdown = true
    uv.shutdown(self.handle, function()
      resp:put(nil)
    end)
  else
    resp:put(nil)
  end
  return resp
end

-- Pipe

local Pipe = Stream:extend()

function Pipe:init(o)
  o = o or {}
  Stream:init(o)
  self.handle = uv.new_pipe(o.ipc or false)
end

-- Process
--
-- This is an abstraction on top of libuv process management.

local Process = util.Object:extend()

function Process:init(o)
  self.cmd = o.cmd
  if path.is(self.cmd) then
    self.cmd = self.cmd.string
  end
  self.cwd = o.cwd or nil
  if path.is(self.cwd) then
    self.cwd = self.cwd.string
  end
  self.args = o.args
  self.pid = nil
  self.handle = nil
  self.completion = async.Future:new()
  self.stdin = o.stdin or Pipe:new()
  self.stdout = o.stdout or Pipe:new()
  self.stderr = o.stderr or Pipe:new()
  self:spawn()
end

function Process:spawn()
  local handle, pid_or_message = uv.spawn(self.cmd, {
    cwd = self.cwd,
    stdio = { self.stdin.handle, self.stdout.handle, self.stderr.handle },
    args = self.args,
  }, function(status, signal)
    self.completion:put({status = status, signal = signal})
    if self.handle then
      uv.close(self.handle)
    end
  end)

  if not handle then
    self.stdout:close()
    self.stderr:close()
    self.stdin:close()
    util.errorf("unable to spawn '%s': %s", self.cmd, pid_or_message)
  end

  self.handle = handle
  self.pid = pid_or_message
end

function Process:shutdown()
  assert(self.handle ~= nil, 'Process.shutdown: handle is nil')
  return self.stdin:shutdown():map(function()
    self.stdout:close()
    self.stderr:close()
    self.stdin:close()
  end)
end

function Process:kill(signal)
  if self.handle and not uv.is_closing(self.handle) then
    uv.process_kill(self.handle, signal or 'sigterm')
  end
end

local function spawn(o)
  return Process:new(o)
end

return {
  Pipe = Pipe,
  spawn = spawn,
  sleep = sleep,
  _uv = uv,
}
