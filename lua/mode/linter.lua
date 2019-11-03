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
  self.id = "linter:" .. o.id
  self.log = logging.get_logger(self.id)
  self.cmd = o.cmd
  self.args = o.args
  self.cwd = o.cwd
  self.produce = o.produce
  self.diagnostics = async.Channel:new()

  self._buffers = {}

  self.on_schedule_run = async.Channel:new()
  self.on_process_started = async.Channel:new()
  self.on_process_completed = async.Channel:new()
  self.on_run_completed = async.Channel:new()
end

function Linter:start(o)
  return self:new(o)
end

function Linter:schedule_run(buf)
  local info = self._buffers[buf.id]
  if not info then
    return
  end
  if info.cancel_run ~= nil then
    info.cancel_run()
  end

  local delay, cancel = uv.sleep(Linter.debounce)
  info.cancel_run = cancel

  self.on_schedule_run:put()
  async.task(function()
    local ok = delay:wait()
    if ok then
      self:run(buf)
    end
  end)
end

function Linter:run(buffer)
  vim.wait()
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
    self.on_run_completed:put()
    return
  end
  self.on_process_started:put()

  local lines = info.buffer:contents_lines()
  for _, line in ipairs(lines) do
    proc.stdin:write(line .. '\n')
  end
  proc.stdin:shutdown()
  local data = proc.stdout:read_all():wait()
  proc:shutdown()

  local status = proc.completion:wait().status
  self.on_process_completed:put()
  log_run("process exited with %d code", status)

  -- check if we are still at the same tick
  if info.tick ~= this_tick then
    log_run("discarding results since buffer has new changes", status)
    self.on_run_completed:put()
  else
    local items = {}
    for line in data:gmatch("[^\r\n]+") do
      local item = self.produce(line, filename)
      if item then
        table.insert(items, item)
      end
    end
    log_run("collected %d diagnostics", #items)
    self.diagnostics:put({{filename = filename, items = items}})
    self.on_run_completed:put()
  end
end

function Linter.did_insert_enter() end

function Linter:did_insert_leave(buffer)
  async.task(function()
    self:run(buffer)
  end)
end

function Linter:did_buffer_enter(buffer)
  async.task(function()
    self:run(buffer)
  end)
end

function Linter:did_change(change)
  local info = self._buffers[change.buffer.id]
  if not info then
    return
  end
  info.tick_queued = change.tick
  local mode = vim._vim.api.nvim_get_mode().mode:sub(1, 1)
  if mode == "n" or mode == "c" then
    self:schedule_run(change.buffer)
  end
end

function Linter:did_open(buffer)
  async.task(function()
    local watcher = BufferWatcher:new { buffer = buffer }
    local info = {
      tick = -1,
      tick_queued = 0,
      cancel_run = nil,
      buffer = buffer,
      watcher = watcher,
      stop_updates = watcher.updates:subscribe(function(change)
        self:did_change(change)
      end),
    }
    self._buffers[buffer.id] = info
    self:run(buffer)
  end)
end

function Linter._shutdown_buffer(info)
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
  self.on_schedule_run:close()
  self.on_process_started:close()
  self.on_process_completed:close()
  self.on_run_completed:close()
end

return Linter
