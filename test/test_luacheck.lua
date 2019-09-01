local vim = require 'mode.vim'
local mode = require 'mode'
local uv = require 'mode.uv'
local async = require 'mode.async'
local language_service = require 'mode.language_service'
local Diagnostics = require 'mode.diagnostics'

mode.configure_linter {
  id = 'luacheck',
  filetype = {'lua'},
  command = function(_)
    return 'luacheck', {
      '--formatter', 'plain',
      '--filename', '%{FILENAME}%',
      '--codes',
      '-'
    }
  end,
  root = function(filename)
    return filename.parent
  end,
  produce = function(line_raw)
    local pattern = '(.+):(%d+):(%d+):%s*%(([WE])%d+%)%s*(.+)'
    local _, _, filename, line, character, kind, message = line_raw:find(pattern)
    line = tonumber(line)
    character = tonumber(character)
    return {
      filename = filename,
      kind = kind,
      range = { start = {line = line - 1, character = character - 1} },
      message = message,
    }
  end
}

local function execute(...)
  vim.wait(true)
  return vim.execute(...)
end

local function edit(filename)
  print("EDIT " .. filename)
  execute("edit " .. filename)
  return vim.Buffer:current()
end

local function feed(input)
  while #input > 0 do
    local written = vim._vim.api.nvim_input(input)
    input = input:sub(written + 1)
  end
  vim.wait(true)
end

local function wait(future)
  future:wait()
  vim.wait()
end

local function test(name, case)
  print("TEST " .. name)
  async.task(function()
    vim.wait()
    case()
  end)
end

test("linter sets signs", function()
  local buf = edit "some.lua"

  execute "set filetype=lua"
  feed "ilocal x = 12<CR>local y = 42<ESC>"
  uv.sleep(100):wait()
  vim.wait()

  local service = language_service:get()
  assert(service)
  wait(service.current_run)

  local warnings_signs = vim.call.sign_getplaced(buf.id, {
    group = Diagnostics.use_warnings_signs.name
  })[1].signs
  assert(#warnings_signs == 2)
  assert(warnings_signs[1].lnum == 1)
  assert(warnings_signs[2].lnum == 2)

  local errors_signs = vim.call.sign_getplaced(buf.id, {
    group = Diagnostics.use_errors_signs.name
  })[1].signs
  assert(#errors_signs == 0)

  execute "quitall!"
end)
