-- Highlights

local util = require 'mode.util'
local vim = require 'mode.vim'

-- API for highlighting rangers within a buffer
--
-- Uses 0-based line and column numbers.
local Highlights = util.Object:extend()

function Highlights:init(o)
  self.namespace = vim._vim.api.nvim_create_namespace(o.name or '')
end

function Highlights:add(item)
  local start, stop = item.range.start, item.range['end']
  if not stop then
    vim._vim.api.nvim_buf_add_highlight(
      item.buffer.id, self.namespace, item.hlgroup,
      start.line, start.character, start.character + 1
    )
  else
    if start.line == stop.line then
      vim._vim.api.nvim_buf_add_highlight(
        item.buffer.id, self.namespace, item.hlgroup,
        start.line, start.character, stop.character
      )
    else
      for line = start.line, stop.line do
        if line == start.line then
          vim._vim.api.nvim_buf_add_highlight(
            item.buffer.id, self.namespace, item.hlgroup,
            line, start.character, -1
          )
        elseif line == stop.line then
          vim._vim.api.nvim_buf_add_highlight(
            item.buffer.id, self.namespace, item.hlgroup,
            line, 0, stop.character
          )
        else
          vim._vim.api.nvim_buf_add_highlight(
            item.buffer.id, self.namespace, item.hlgroup,
            line, 0, -1
          )
        end
      end
    end
  end
end

function Highlights:clear(buffer)
  vim._vim.api.nvim_buf_clear_namespace(buffer.id, self.namespace, 0, -1)
end

return {
  Highlights = Highlights,
}
