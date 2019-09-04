local util = require 'mode.util'
local vim = require 'mode.vim'
local async = require 'mode.async'

-- Vim utils

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

-- Test runner

local Runner = {
  state = {failures = 0},
  cases = {},
  lifecycle = {
    after_each = {},
    before_each = {},
  },
}

function Runner:run(testsuite_name)
  local latch = #self.cases
  async.task(function()
    print(string.format("*** TEST SUITE %s", testsuite_name))
    for _, case in ipairs(self.cases) do
      print(string.format("TEST >> %s", case.name))
      execute "silent %%bdelete!"
      -- Run after_each
      vim.wait(true)
      for _, t in ipairs(self.lifecycle.before_each) do
        local ok, msg = pcall(t.run)
        if not ok then
          print(string.format("LIFECYCLE FAIL before_each: %s", msg))
        end
      end
      -- Run test case
      vim.wait(true)
      do
        local _, msg = pcall(case.run)
        latch = latch - 1
        if msg then
          self.state.failures = self.state.failures + 1
          print(string.format("TEST FAIL %s: %s", case.name, msg))
        else
          print(string.format("TEST OK %s", case.name))
        end
      end
      -- Run after_each
      vim.wait(true)
      for _, t in ipairs(self.lifecycle.after_each) do
        local ok, msg = pcall(t.run)
        if not ok then
          print(string.format("LIFECYCLE FAIL after_each: %s", msg))
        end
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

-- Test runner test API

local function test(name, run)
  table.insert(Runner.cases, {run = run, name = name})
end

local function before_each(run)
  table.insert(Runner.lifecycle.before_each, {run = run})
end

local function after_each(run)
  table.insert(Runner.lifecycle.after_each, {run = run})
end

return {
  Runner = Runner,
  dofile = util.dofile,
  edit = edit,
  execute = execute,
  test = test,
  before_each = before_each,
  after_each = after_each,
  feed = feed,
  wait = wait,
}
