local util = require 'mode.util'
local vim = require 'mode.vim'

local Log = util.Object:extend()

Log.filetype = 'mode.log'

function Log:init(_)
  self.buffer = vim.Buffer:create { scratch = true; listed = true; }
  self.buffer.options.modifiable = false
  self.buffer.options.filetype = Log.filetype
  self.buffer:set_name('** mode **')
end

function Log:info(logger, msg, ...)
  vim.wait()
  msg = string.format(msg, ...)
  local time = vim.call.strftime('%T', vim.call.localtime())
  local line = string.format('%s %s %s', time, logger, msg)
  self.buffer.options.modifiable = true
  self.buffer:append_lines({line})
  self.buffer.options.modifiable = false
end

local Logger = util.Object:extend()

function Logger:init(o)
  self.log = o.log
  self.id = o.id
end

function Logger:info(msg, ...)
  self.log:info(self.id, msg, ...)
end

local log = nil

local function get_logger(id)
  if not log then
    log = Log:new()
  end
  return Logger:new { log = log, id = id }
end

vim.autocommand.register {
  event = vim.autocommand.BufEnter,
  pattern = '*',
  action = function(ev)
    if ev.buffer.options.filetype == Log.filetype then
      local api = vim._vim.api
      api.nvim_win_set_option(api.nvim_get_current_win(), 'wrap', false)
    end
  end
}

return {
  get_logger = get_logger,
}
