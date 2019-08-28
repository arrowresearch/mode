local vim = require 'mode.vim'
local Modal = require 'mode.modal'

local function run(o)
  assert(o.cmd, 'missing command')
  assert(o.on_result, 'missing on_result callback')

  local win = vim.call.win_getid()
  local width = vim._vim.api.nvim_win_get_width(win)
  local height = vim._vim.api.nvim_win_get_height(win)
  local row
  local size = 10

  if height > 15 then
    row = height - size
    height = size
  else
    row = 0
    size = height
    height = height
  end

  local filename = vim.call.tempname()
  local buf = vim._vim.api.nvim_create_buf(false, true)
  local fwin = vim._vim.api.nvim_open_win(buf, true, {
    relative = 'win',
    style = 'minimal',
    height = height,
    width = width,
    row = row + 1,
    col = 0,
  })
  vim._vim.api.nvim_win_set_option(fwin, 'winhl', 'Normal:MyHighlight')
  vim.execute [[
    startinsert
  ]]

  Modal:close()

  local prompt = o.prompt or '> '
  vim.termopen({
    cmd = string.format(
      [[%s | fzy --prompt "%s" --lines %i > %s]],
      o.cmd, prompt, size, filename
    ),
    on_exit = function()
      vim.execute [[
        bdelete!
      ]]
      vim.call.win_gotoid(win)
      if vim.call.filereadable(filename) then
        local selected = vim.call.readfile(filename)[1]
        o.on_result(selected)
      end
      vim.call.delete(filename)
    end
  })
end

local function files()
  run {
    prompt = 'files> ',
    cmd = 'ag -l',
    on_result = function(filename)
      if filename then
        vim.execute([[edit %s]], filename)
      end
    end
  }
end

return {
  run = run,
  files = files
}
