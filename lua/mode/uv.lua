--
-- High-level wrapper for libuv API.
--

local uv = vim.loop
local util = require 'mode.util'
local async = require 'mode.async'

-- Stream

local Stream = util.Object:extend()

function Stream:init()
  self.closed = false
end

function Stream:write(data)
  local status = async.Future:new()
  uv.write(self.handle, data, function(err)
    status:put(err)
  end)
  return status
end

function Stream:read_start(f)
  assert(not self.closed, 'Stream is closed')
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

function Stream:read_all()
  assert(not self.closed, 'Stream is closed')
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
  if not uv.is_closing(self.handle) then
    self.closed = true
    uv.close(self.handle)
  end
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
  self.cwd = o.cwd or nil
  self.args = o.args
  self.pid = nil
  self.handle = nil
  self.exit_code = async.Future:new()
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
  assert(handle, "Unable to spawn a process")
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

return {
  Pipe = Pipe,
  Process = Process,
  _uv = uv,
}
