local vim = require 'mode.vim'

local Modal = {
  current = nil
}

function Modal:open(buffer, message)
  if self.current then
    vim._vim.api.nvim_win_close(self.current.win, true)
    self.current = nil
  end
  local win = vim.call.win_getid()
  local width = vim._vim.api.nvim_win_get_width(win)
  local height = vim._vim.api.nvim_win_get_height(win)
  local size = 6
  local buf = vim._vim.api.nvim_create_buf(false, true)
  local sep = string.rep("━", width)
  local lines = {sep}
  for line in string.gmatch(message, '([^\n\r]+)') do
    table.insert(lines, line)
  end
  vim._vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local fwin = vim._vim.api.nvim_open_win(buf, false, {
    relative = 'win',
    style = 'minimal',
    height = size,
    width = width,
    row = height - size + 1,
    col = 0,
  })
  assert(fwin ~= 0, 'Error creating window')
  vim._vim.api.nvim_win_set_option(fwin, 'winhighlight', 'Normal:MyHighlight')
  self.current = { win = fwin, buffer = buffer }
end

function Modal:close()
  if self.current then
    vim._vim.api.nvim_win_close(self.current.win, true)
    self.current = nil
  end
end

vim.autocommand.register {
  event = {
    vim.autocommand.InsertEnter,
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
    if Modal.current and Modal.current.buffer ~= ev.buffer then
      Modal:close()
    end
  end
}

return Modal
