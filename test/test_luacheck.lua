-- luacheck: globals __DIR__

local t = require 'mode.test'
local util = require 'mode.util'
local vim = require 'mode.vim'
local LanguageService = require 'mode.language_service'
local Diagnostics = require 'mode.diagnostics'

util.dofile(__DIR__ / ".." / "mode" / "filetype" / "lua.lua")

t.test("luacheck: linter sets signs", function()
  local buf = t.edit "some.lua"
  t.execute [[set filetype=lua]]
  t.feed [[ilocal x = 12\<CR>local y = 42\<ESC>]]

  local service = LanguageService:get()
  assert(service)
  t.wait(service.current_run)

  local warnings_signs = vim.call.sign_getplaced(buf.id, {
    group = Diagnostics.use_warnings_signs.name
  })[1].signs
  assert(#warnings_signs == 2)
  assert(warnings_signs[1].lnum == 1)
  assert(warnings_signs[2].lnum == 2)
end)
