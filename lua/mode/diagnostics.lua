-- Diagnostics

local util = require 'mode.util'
local vim = require 'mode.vim'
local highlights = require 'mode.highlights'
local signs = require 'mode.signs'

local Diagnostics = {
  use_quickfix_list = true,
  use_highlights = highlights.Highlights:new {
    name = 'mode-diag-highlights'
  },
  use_errors_signs = signs.Signs:new {
    name = 'mode-diag-errors',
    text = '✖',
    texthl = 'ModeError',
    priority = 100,
  },
  use_warnings_signs = signs.Signs:new {
    name = 'mode-diag-warnings',
    text = '✖',
    texthl = 'ModeWarning',
    priority = 90,
  },
  updated = false,
  by_filename = {}
}

function Diagnostics:get(filename)
  return self.by_filename[filename.string] or {}
end

function Diagnostics:set(filename, items)
  items = items or {}
  items = util.array_copy(items)
  table.sort(items, function(a, b)
    if a.range.start.line < b.range.start.line then
      return true
    elseif
      a.range.start.line == b.range.start.line
      and a.range.start.character < b.range.start.character
    then
      return true
    else
      return false
    end
  end)
  self.by_filename[filename.string] = items
  self.updated = false
end

function Diagnostics:update_for_buffer(buffer)
  local items = self.by_filename[vim._vim.api.nvim_buf_get_name(buffer)]
  if not items then
    return
  end
  if self.use_highlights then
    self.use_highlights:clear(buffer)
  end
  for _, item in ipairs(items) do
    local hlgroup = 'ModeError'
    if item.kind == 'W' then
      hlgroup = 'ModeWarning'
    end
    if self.use_highlights then
      self.use_highlights:add {
        hlgroup = hlgroup,
        buffer = buffer,
        range = item.range,
      }
    end
    if self.use_warnings_signs and item.kind == 'W' then
      self.use_warnings_signs:place {
        buffer = buffer,
        line = item.range.start.line,
      }
    elseif self.use_errors_signs then
      self.use_errors_signs:place {
        buffer = buffer,
        line = item.range.start.line,
      }
    end
  end
end

function Diagnostics:update()
  if self.updated then
    return
  end
  -- TODO(andreypopp): set signs per file
  if self.use_warnings_signs then
    self.use_warnings_signs:unplace_all()
  end
  if self.use_errors_signs then
    self.use_errors_signs:unplace_all()
  end
  if self.use_quickfix_list then
    vim.call.setqflist({}, 'r')
  end

  local qf = {}

  for filename, items in pairs(self.by_filename) do
    local buffer = vim.call.bufnr(filename)
    local buffer_loaded = buffer ~= -1

    if self.use_highlights then
      self.use_highlights:clear(buffer)
    end

    for _, item in ipairs(items) do
      if buffer_loaded then
        if self.use_warnings_signs and item.kind == 'W' then
          self.use_warnings_signs:place {
            buffer = buffer,
            line = item.range.start.line,
          }
        elseif self.use_errors_signs then
          self.use_errors_signs:place {
            buffer = buffer,
            line = item.range.start.line,
          }
        end
      end
      if self.use_highlights and buffer_loaded then
        local hlgroup = 'ModeError'
        if item.kind == 'W' then
          hlgroup = 'ModeWarning'
        end
        self.use_highlights:add {
          hlgroup = hlgroup,
          buffer = buffer,
          range = item.range,
        }
      end
      table.insert(qf, {
        filename = item.filename.string,
        lnum = item.range.start.line + 1,
        col = item.range.start.character + 1,
        text = item.message,
        type = item.kind,
      })
    end
  end
  if self.use_quickfix_list then
    vim.call.setqflist(qf, 'r')
  end
  self.updated = true
end

-- Make sure we update diagnostics for a buffer we just openned up.
vim.autocommand.register {
  event = {vim.autocommand.BufEnter, vim.autocommand.BufNew},
  pattern = '*',
  action = function(ev)
    Diagnostics:update_for_buffer(ev.buffer)
  end
}

return Diagnostics
