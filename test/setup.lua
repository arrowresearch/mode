-- luacheck: globals vim

local cwd = vim.api.nvim_call_function('getcwd', {})
package.path = cwd .. '/lua/?.lua;' .. package.path

local vim = require 'mode.vim'

vim.execute "set noswapfile"
