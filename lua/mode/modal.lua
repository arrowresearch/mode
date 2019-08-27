local vim = require 'mode.vim'

local Modal = {
  win = nil,
}

function Modal:open(message)
  self:close()
  local win = vim.call.win_getid()
  local width = vim._vim.api.nvim_win_get_width(win)
  local height = vim._vim.api.nvim_win_get_height(win)
  local size = 4
  local buf = vim._vim.api.nvim_create_buf(false, true)
  vim._vim.api.nvim_buf_set_lines(buf, 0, -1, false, { message })
  self.win = vim._vim.api.nvim_open_win(buf, false, {
    relative = 'win',
    style = 'minimal',
    height = size,
    width = width,
    row = height - size + 1,
    col = 0,
  })
end

function Modal:close()
  if self.win then
    vim._vim.api.nvim_win_close(self.win, true)
    self.win = nil
  end
end

vim.autocommand.register {
  event = vim.autocommand.InsertEnter,
  pattern = '*',
  action = function()
    Modal:close()
  end
}

return Modal
