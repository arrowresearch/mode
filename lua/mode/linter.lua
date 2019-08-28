-- luacheck: globals

local async = require 'mode.async'
local path = require 'mode.path'
local util = require 'mode.util'
local vim = require 'mode.vim'
local uv = require 'mode.uv'

local BufferWatcherRecord = util.Object:extend()

function BufferWatcherRecord:init(o)
  self.refcount = 0
  self.updates = async.Channel:new()
  self.buffer = o.buffer
  self.is_utf8 = o.is_utf8 == nil and true or o.is_utf8
end

function BufferWatcherRecord:_start()
  assert(vim._vim.api.nvim_buf_attach(self.buffer, false, {
    on_lines=function(_, _, tick, start, stop, stopped, bytes, _, units)
      async.task(function()
        self.updates:put {
          buffer = self.buffer,
          tick = tick,
          start = start,
          stop = stop,
          stopped = stopped,
          bytes = bytes,
          units = units
        }
      end)
    end,
    utf_sizes=false
  }))
end

function BufferWatcherRecord:use()
  self.refcount = self.refcount + 1
  if self.refcount == 1 then
    self:_start()
  end
end

function BufferWatcherRecord:release()
  self.refcount = self.refcount - 1
  if self.refcount == 0 then
    -- TODO(andreypopp): this function isn't available for the current neovim
    -- master, check back with neovim folks.
    if vim._vim.api.nvim_buf_detach then
      vim._vim.api.nvim_buf_detach(self.buffer)
    end
  end
end

function BufferWatcherRecord:shutdown()
  vim._vim.api.nvim_buf_detach(self.buffer)
  self.updates:close()
end

local BufferWatcher = {
  _watchers = {}
}

function BufferWatcher:watch(buffer)
  local existing = self._watchers[buffer]
  if existing then
    existing:use()
    return existing
  end

  local watcher = BufferWatcherRecord:new {
    buffer = buffer,
  }
  self._watchers[buffer] = watcher

  watcher:use()
  return watcher
end

local Linter = util.Object:extend()

function Linter:init(o)
  self.cmd = o.cmd
  self.args = o.args
  self.cwd = o.cwd
  self.produce = o.produce
  self.diagnostics = async.Channel:new()

  self._buffers = {}
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
  local buffer_info = self._buffers[buffer]
  if not buffer_info then
    return
  end
  if buffer_info.tick >= buffer_info.tick_queued then
    return
  end

  local this_tick = buffer_info.tick_queued
  buffer_info.tick = this_tick

  local args = {}
  for _, arg in ipairs(self.args) do
    arg = arg:gsub("%%{FILENAME}%%", buffer_info.filename.string)
    table.insert(args, arg)
  end

  local proc = uv.Process:new {
    cmd = self.cmd,
    args = args,
    cwd = self.cwd,
  }
  -- write lines
  vim.wait()
  local lines = vim._vim.api.nvim_buf_get_lines(buffer, 0, -1, true)
  for _, line in ipairs(lines) do
    proc.stdin:write(line .. '\n')
  end
  proc.stdin:shutdown()
  -- read data and produce diagnostics
  local data = proc.stdout:read_all():wait()
  vim.wait()
  -- check if we are still at the same tick
  if buffer_info.tick ~= this_tick then
    return
  end
  local items = {}
  for line in data:gmatch("[^\r\n]+") do
    local item = self.produce(line)
    if item then
      table.insert(items, item)
    end
  end
  self.diagnostics:put({{filename = filename, items = items}})
  -- shutdown proc
  proc:shutdown()
end

function Linter.did_insert_enter() end

function Linter:did_insert_leave(buffer)
  self:_run(buffer)
end

function Linter:did_change(change)
  local buffer_info = self._buffers[change.buffer]
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
  local watcher = BufferWatcher:watch(buffer)
  vim.wait()
  local buffer_info = {
    filename = path.split(vim._vim.api.nvim_buf_get_name(buffer)),
    tick = -1,
    tick_queued = 0,
    watcher = watcher,
    stop_updates = watcher.updates:subscribe(function(change)
      self:did_change(change)
    end),
  }
  self._buffers[buffer] = buffer_info
  self:_run(buffer)
end

function Linter:shutdown()
  for _, buffer_info in pairs(self._buffers) do
    if buffer_info.proc then
      buffer_info.proc:shutdown()
    end
    buffer_info.watcher:release()
    buffer_info.stop_updates()
  end
end

return Linter
