local util = require 'mode.util'
local vim = require 'mode.vim'
local async = require 'mode.async'

local function execute(...)
  vim.wait(true)
  return vim.execute(...)
end

local function edit(filename)
  execute("edit! " .. filename)
  return vim.Buffer:current()
end

local function feed(input)
  vim.call.ModeRun {input}
  vim.wait(true)
end

local function wait(future)
  future:wait()
  vim.wait(true)
end

local state = {failures = 0}
local cases = {}

local function test(name, run)
  table.insert(cases, {run = run, name = name})
end

local function run()
  local latch = #cases
  async.task(function()
    for _, case in ipairs(cases) do
      print(string.format("TEST >> %s", case.name))
      execute "silent %%bdelete!"
      vim.wait(true)
      local _, msg = pcall(case.run)
      latch = latch - 1
      if msg then
        state.failures = state.failures + 1
        print(string.format("TEST FAIL %s: %s", case.name, msg))
      else
        print(string.format("TEST OK %s", case.name))
      end
    end
  end)
  while true do
    vim.execute [[sleep 5m]]
    if latch == 0 then
      break
    end
  end
end

return {
  dofile = util.dofile,
  state = state,
  edit = edit,
  execute = execute,
  test = test,
  feed = feed,
  wait = wait,
  run = run,
}
