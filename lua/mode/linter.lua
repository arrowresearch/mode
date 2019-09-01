local async = require 'mode.async'
local util = require 'mode.util'
local vim = require 'mode.vim'
local uv = require 'mode.uv'
local BufferWatcher = require 'mode.buffer_watcher'

local Linter = util.Object:extend()

Linter.type = "linter"

function Linter:init(o)
  self.cmd = o.cmd
  self.args = o.args
  self.cwd = o.cwd
  self.produce = o.produce
  self.diagnostics = async.Channel:new()

  self._buffers = {}

  self.current_run = async.Future:new()
  self.current_run:put()
end

function Linter:start(o)
  return self:new(o)
end

function Linter:_queue_run(buffer)
  async.task(function()
    uv.sleep(700):wait()
    self:_run(buffer)
  end)
end

function Linter:_run(buffer)
  local buffer_info = self._buffers[buffer.id]
  if not buffer_info then
    return
  end
  if buffer_info.tick >= buffer_info.tick_queued then
    return
  end

  self.current_run = async.Future:new()
  local current_run = self.current_run

  vim.wait()
  local filename = buffer:filename()

  local this_tick = buffer_info.tick_queued
  buffer_info.tick = this_tick

  local args = {}
  for _, arg in ipairs(self.args) do
    arg = arg:gsub("%%{FILENAME}%%", filename.string)
    table.insert(args, arg)
  end

  local proc = uv.Process:new {
    cmd = self.cmd,
    args = args,
    cwd = self.cwd,
  }
  vim.wait()
  local lines = buffer:contents_lines()
  for _, line in ipairs(lines) do
    proc.stdin:write(line .. '\n')
  end
  proc.stdin:shutdown()
  local data = proc.stdout:read_all():wait()
  proc:shutdown()

  -- check if we are still at the same tick
  if buffer_info.tick ~= this_tick then
    current_run:put()
  else
    local items = {}
    for line in data:gmatch("[^\r\n]+") do
      local item = self.produce(line)
      if item then
        table.insert(items, item)
      end
    end
    self.diagnostics:put({{filename = filename, items = items}})
    current_run:put()
  end
end

function Linter.did_insert_enter() end

function Linter:did_insert_leave(buffer)
  self:_run(buffer)
end

function Linter:did_buffer_enter(buffer)
  self:_run(buffer)
end

function Linter:did_change(change)
  local buffer_info = self._buffers[change.buffer.id]
  if not buffer_info then
    return
  end
  buffer_info.tick_queued = change.tick
  local mode = vim._vim.api.nvim_get_mode().mode
  if mode:sub(1, 1) == "n" then
    self:_queue_run(change.buffer)
  end
end

function Linter:did_open(buffer)
  local watcher = BufferWatcher:new { buffer = buffer }
  vim.wait()
  local buffer_info = {
    tick = -1,
    tick_queued = 0,
    watcher = watcher,
    stop_updates = watcher.updates:subscribe(function(change)
      self:did_change(change)
    end),
  }
  self._buffers[buffer.id] = buffer_info
  self:_run(buffer)
end

function Linter._shutdown_buffer(buffer_info)
  if buffer_info.proc then
    buffer_info.proc:shutdown()
  end
  buffer_info.watcher:shutdown()
  buffer_info.stop_updates()
end

function Linter:did_close(buffer)
  local buffer_info = self._buffers[buffer.id]
  if buffer_info then
    self._shutdown_buffer(buffer_info)
  end
end

function Linter:shutdown()
  for _, buffer_info in pairs(self._buffers) do
    self._shutdown_buffer(buffer_info)
  end
end

return Linter
