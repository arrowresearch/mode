local util = require 'mode.util'
local vim = require 'mode.vim'

local Position = util.Object:extend()

function Position:init(o)
  self.line = o.line
  self.character = o.character
end

function Position.__eq(a, b)
  return a.line == b.line and a.character == b.character
end

function Position.__lt(a, b)
  if a.line < b.line then
    return true
  elseif a.line == b.line and a.character < b.character then
    return true
  else
    return false
  end
end

function Position.__le(a, b)
  return a == b or a < b
end

function Position:current()
  local p = vim.call.getpos('.')
  return self:new {
    line = p[2] - 1,
    character = p[3] - 1,
  }
end

return Position
