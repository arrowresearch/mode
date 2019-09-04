local t = require 'mode.test'
local fs = require 'mode.fs'
local vim = require 'mode.vim'
local Linter = require 'mode.linter'

Linter.debounce = 0

local linter
local diagnostics_mock
local diagnostics_received

t.before_each(function()
  diagnostics_mock = {}
  diagnostics_received = {}
  linter = Linter:start {
    id = 'test-linter',
    cmd = 'echo',
    args = {'line1\nline2\n'},
    cwd = fs.cwd(),
    produce = function(_)
      return table.remove(diagnostics_mock)
    end
  }
  linter.diagnostics:subscribe(function(items)
    for _, item in ipairs(items) do
      table.insert(diagnostics_received, item)
    end
  end)
end)

t.after_each(function()
  diagnostics_mock = {}
  diagnostics_received = {}
  linter:shutdown()
  linter = nil
end)

t.test("linter: run on did_open", function()
  local buf = t.edit "file.txt"

  diagnostics_mock = {
    {
      filename = buf:filename().string,
      kind = 'E',
      range = { start = {line = 0, character = 3} },
      message = 'Error Here',
    },
    {
      filename = buf:filename().string,
      kind = 'W',
      range = { start = {line = 1, character = 6} },
      message = 'Warning Here',
    }
  }

  linter:did_open(buf)
  t.wait(linter.current_run)

  assert(#diagnostics_received == 1)
  assert(diagnostics_received[1].filename == buf:filename())
  assert(#diagnostics_received[1].items == 2)
end)

t.test("linter: run on changes", function()
  local buf = t.edit "file.txt"

  -- Open buffer
  linter:did_open(buf)
  t.wait(linter.current_run)

  assert(#diagnostics_received == 1)
  assert(diagnostics_received[1].filename == buf:filename())
  assert(#diagnostics_received[1].items == 0)

  -- Reset diagnostics
  diagnostics_received = {}
  diagnostics_mock = {
    {
      filename = buf:filename().string,
      kind = 'E',
      range = { start = {line = 0, character = 3} },
      message = 'Error Here',
    },
    {
      filename = buf:filename().string,
      kind = 'W',
      range = { start = {line = 1, character = 6} },
      message = 'Warning Here',
    }
  }

  -- Change buffer
  linter:did_insert_enter(buf)
  t.feed [[isometext here<Esc>]]
  linter:did_insert_leave(buf)
  t.wait(linter.current_run)

  assert(#diagnostics_received == 1)
  assert(diagnostics_received[1].filename == buf:filename())
  assert(#diagnostics_received[1].items == 2)

end)
