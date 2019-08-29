local async = require 'mode.async'
local util = require 'mode.util'
local vim = require 'mode.vim'

local BufferWatcher = util.Object:extend()

function BufferWatcher:init(o)
  self.updates = async.Channel:new()
  self.buffer = o.buffer
  self.is_utf8 = o.is_utf8 == nil and true or o.is_utf8
  self.is_shutdown = false
  self:_start()
end

function BufferWatcher:_start()
  assert(vim._vim.api.nvim_buf_attach(self.buffer.id, false, {
    on_lines=function(_, _, tick, start, stop, stopped, bytes, _, units)
      if self.is_shutdown then
        return true
      end
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
    utf_sizes=not self.is_utf8
  }))
end

function BufferWatcher:shutdown()
  self.is_shutdown = true
  self.updates:close()
end

return BufferWatcher
