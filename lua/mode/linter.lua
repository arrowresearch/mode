local async = require 'mode.async'
local util = require 'mode.util'
local vim = require 'mode.vim'
local logging = require 'mode.logging'
local uv = require 'mode.uv'
local BufferWatcher = require 'mode.buffer_watcher'

local Linter = util.Object:extend()

Linter.debounce = 700
Linter.type = "linter"

function Linter:init(o)
  self.log = logging.get_logger(string.format('linter:%s', o.id))
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
    uv.sleep(Linter.debounce):wait()
    self:_run(buffer)
  end)
end

function Linter:_run(buffer)
  local info = self._buffers[buffer.id]
  if not info then
    return
  end
  if info.tick >= info.tick_queued then
    return
  end

  local this_tick = info.tick_queued
  local this_name = vim.call.fnamemodify(info.buffer:name(), ':.')
  info.tick = this_tick

  local function log_run(line, ...)
    vim.wait()
    local msg = string.format(line, ...)
    self.log:info("%s@%d %s", this_name, this_tick, msg)
  end

  log_run("executing '%s'", self.cmd)

  self.current_run = async.Future:new()
  local current_run = self.current_run

  vim.wait()
  local filename = info.buffer:filename()

  local args = {}
  for _, arg in ipairs(self.args) do
    arg = arg:gsub("%%{FILENAME}%%", filename.string)
    table.insert(args, arg)
  end

  local proc_status, proc = pcall(uv.spawn, {
    cmd = self.cmd,
    args = args,
    cwd = self.cwd,
  })
  if not proc_status then
    log_run("error: %s", proc)
    return
  end
  local lines = info.buffer:contents_lines()
  for _, line in ipairs(lines) do
    proc.stdin:write(line .. '\n')
  end
  proc.stdin:shutdown()
  local data = proc.stdout:read_all():wait()
  proc:shutdown()

  local status = proc.completion:wait().status
  log_run("process exited with %d code", status)

  -- check if we are still at the same tick
  if info.tick ~= this_tick then
    log_run("discarding results since buffer has new changes", status)
    current_run:put()
  else
    local items = {}
    for line in data:gmatch("[^\r\n]+") do
      local item = self.produce(line)
      if item then
        table.insert(items, item)
      end
    end
    log_run("collected %d diagnostics", #items)
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
  local info = self._buffers[change.buffer.id]
  if not info then
    return
  end
  info.tick_queued = change.tick
  local mode = vim._vim.api.nvim_get_mode().mode:sub(1, 1)
  if mode == "n" or mode == "c" then
    self:_queue_run(change.buffer)
  end
end

function Linter:did_open(buffer)
  local watcher = BufferWatcher:new { buffer = buffer }
  vim.wait()
  local info = {
    tick = -1,
    tick_queued = 0,
    buffer = buffer,
    watcher = watcher,
    stop_updates = watcher.updates:subscribe(function(change)
      self:did_change(change)
    end),
  }
  self._buffers[buffer.id] = info
  self:_run(buffer)
end

function Linter._shutdown_buffer(info)
  if info.proc then
    info.proc:shutdown()
  end
  info.watcher:shutdown()
  info.stop_updates()
  info.buffer = nil
  info.watcher = nil
  info.stop_updates = nil
end

function Linter:did_close(buffer)
  local info = self._buffers[buffer.id]
  if info then
    self._shutdown_buffer(info)
  end
  self._buffers[buffer.id] = nil
end

function Linter:shutdown()
  for id, info in pairs(self._buffers) do
    self._shutdown_buffer(info)
    self._buffers[id] = nil
  end
end

return Linter
