-- BufferWatcher
--
-- A mechanism to be notified of when a specified buffer has changed.

local async = require 'mode.async'
local util = require 'mode.util'
local vim = require 'mode.vim'

local BufferWatcher = util.Object:extend()

function BufferWatcher:init(o)
  self.updates = async.Channel:new()
  self.buffer = o.buffer
  self.is_utf8 = o.is_utf8 == nil and true or o.is_utf8
  self.is_shutdown = false
  self.track_start_column = o.track_start_column or false
  if self.track_start_column then
    self.lines = self.buffer:contents_lines()
  else
    self.lines = nil
  end
  self:_start()
end

function BufferWatcher:_start()
  assert(vim._vim.api.nvim_buf_attach(self.buffer.id, false, {
    on_lines=function(_, _, tick, start, stop, stopped, bytes, _, units)
      if self.is_shutdown then
        return true
      end

      local start_coln = nil
      if self.track_start_column then
        local line_1 = self.lines[start + 1]
        local updated_lines = self.buffer:contents_lines(start, stopped)
        local updated_line_1 = updated_lines[1]

        -- Compare first line of the change
        start_coln = line_1 and #line_1 or 0
        if updated_line_1 ~= nil and line_1 ~= nil then
          for i = 1,#line_1 do
            if line_1:byte(i) ~= updated_line_1:byte(i) then
              start_coln = i - 1 -- make it 0-based
              break
            end
          end
        end

        -- Update self.lines with updated lines
        local new_lines = {}
        for lnum = 1,start do
          table.insert(new_lines, self.lines[lnum])
        end
        for _,line in ipairs(updated_lines) do
          table.insert(new_lines, line)
        end
        for lnum = stop+1,#self.lines do
          table.insert(new_lines, self.lines[lnum])
        end
        self.lines = new_lines
      end

      self.updates:put {
        buffer = self.buffer,
        tick = tick,
        start = start,
        start_coln = start_coln,
        stop = stop,
        stopped = stopped,
        bytes = bytes,
        units = units
      }
    end,
    utf_sizes=not self.is_utf8
  }))
end

function BufferWatcher:shutdown()
  self.is_shutdown = true
  self.updates:close()
end

return BufferWatcher
