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
local lifecycle_after_each = {}
local lifecycle_before_each = {}

local function test(name, run)
  table.insert(cases, {run = run, name = name})
end

local function before_each(run)
  table.insert(lifecycle_before_each, {run = run})
end

local function after_each(run)
  table.insert(lifecycle_after_each, {run = run})
end

local function run()
  local latch = #cases
  async.task(function()
    for _, case in ipairs(cases) do
      print(string.format("TEST >> %s", case.name))
      execute "silent %%bdelete!"
      -- Run after_each
      vim.wait(true)
      for _, t in ipairs(lifecycle_before_each) do
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
          state.failures = state.failures + 1
          print(string.format("TEST FAIL %s: %s", case.name, msg))
        else
          print(string.format("TEST OK %s", case.name))
        end
      end
      -- Run after_each
      vim.wait(true)
      for _, t in ipairs(lifecycle_after_each) do
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

return {
  dofile = util.dofile,
  state = state,
  edit = edit,
  execute = execute,
  test = test,
  before_each = before_each,
  after_each = after_each,
  feed = feed,
  wait = wait,
  run = run,
}
