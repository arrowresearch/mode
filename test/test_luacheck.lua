-- luacheck: globals __DIR__

local t = require 'mode.test'
local LanguageService = require 'mode.language_service'
local Diagnostics = require 'mode.diagnostics'
local Linter = require 'mode.linter'

Linter.debounce = 0

t.dofile(__DIR__ / ".." / "mode" / "filetype" / "lua.lua")

t.test("luacheck: sets warnings signs", function()
  local buf = t.edit "some.lua"
  t.execute [[set filetype=lua]]
  t.feed [[ilocal x = 12\<CR>local y = 42\<ESC>]]

  local service = LanguageService:get()
  assert(service)
  t.wait(service.on_run_completed:next())

  local signs = Diagnostics.use_warnings_signs:get(buf)
  assert(#signs == 2)
  assert(signs[1].lnum == 1)
  assert(signs[2].lnum == 2)
end)

t.test("luacheck: sets errors signs", function()
  local buf = t.edit "some.lua"
  t.execute [[set filetype=lua]]
  t.feed [[ilocal x\<CR>\<ESC>]]

  local service = LanguageService:get()
  assert(service)
  t.wait(service.on_run_completed:next())

  local signs = Diagnostics.use_errors_signs:get(buf)
  assert(#signs == 1)
  assert(signs[1].lnum == 2)
end)
