local util = require 'mode.util'
local vim = require 'mode.vim'

local Modal = {
  current = nil
}

function Modal:open(o)
  assert(o.lines ~= nil)
  local lines = util.table.from_iterator(o.lines)

  local width = vim.ui.options.columns
  local height = math.max(math.min(o.size or 8, #lines + 2))

  local row = 1

  local content = {}
  do
    local ch = '─'
    local top
    if o.title then
      local right = string.rep(ch, 1)
      local left = string.rep(ch, width - #o.title - 1)
      top = left .. o.title .. right
    else
      top = string.rep(ch, width)
    end
    local bottom = string.rep(ch, width)
    table.insert(content, top)
    for i = 1, height - 2 do
      table.insert(content, lines[i] or '')
    end
    table.insert(content, bottom)
  end

  local bailout = true
  do
    if self.current ~= nil and #self.current.content == #content then
      for i = 1, #content do
        if content[i] ~= self.current.content[i] then
          bailout = false
          break
        end
      end
    else
      bailout = false
    end
  end
  if bailout then
    return
  end

  vim.show("OPEN")
  self:close()

  local buf = vim.Buffer:create {
    listed = false,
    scratch = true,
    lines = content,
  }

  local win = vim.Window:open_floating {
    buf = buf,
    enter = false,
    relative = 'cursor',
    style = 'minimal',
    height = height,
    width = width,
    row = row,
    col = 0,
  }
  win.options.winhighlight = 'Normal:MyHighlight'
  win.options.wrap = false
  win.options.cursorline = false
  win.options.signcolumn = 'no'

  self.current = {win = win, content = content}
end

function Modal:close()
  if self.current ~= nil then
    self.current.win:close { force = true }
    self.current = nil
  end
end

vim.autocommand.register {
  event = {
    vim.autocommand.InsertEnter,
    vim.autocommand.CmdlineEnter,
  },
  pattern = '*',
  action = function()
    Modal:close()
  end
}

vim.autocommand.register {
  event = {
    vim.autocommand.BufEnter,
  },
  pattern = '*',
  action = function(ev)
    if Modal.current and Modal.current.win.buffer() ~= ev.buffer then
      Modal:close()
    end
  end
}

return Modal
