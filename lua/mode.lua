-- luacheck: globals vim

local util = require 'mode.util'
local path = require 'mode.path'
local vim = require 'mode.vim'
local async = require 'mode.async'
local jsonrpc = require 'mode.jsonrpc'
local uv = require 'mode.uv'
local P = path.split

-- Task
--
-- This is a wrapper around Lua coroutine which provides conveniences.
--
-- To create a task one does:
--
--   local task = Task:new(function() ... end)
--
-- Then we can wait for its completion:
--
--   task.completed:wait()
--
-- Or we can subscribe to its completion:
--
--   task.completed:subscribe(function() ... end)
--

local Task = util.Object:extend()

function Task:init(f)
  self.completed = async.Future:new()
  self.coro = coroutine.create(function()
    f()
    self.completed:put()
  end)
  assert(coroutine.resume(self.coro))
end

function Task:wait()
  return self.completed:wait()
end

-- Vim API

-- Test

local capabilities = {
  textDocument = {
    publishDiagnostics={relatedInformation=true},
  },
  offsetEncoding = {'utf-8', 'utf-16'},
}

local function find_nearest(curr, fname)
  local stat, err = uv._uv.fs_stat((curr / fname).string)
  if stat ~= nil then
    return curr
  else
    local next = path.parent(cur)
    if next == nil then
      return nil
    else
      return find_nearest(next, fname)
    end
  end
end

Task:new(function()
  local proc = uv.Process:new({
    cmd = './node_modules/.bin/flow',
    args = {'lsp'}
  })

  local client = jsonrpc.JSONRPCClient:new({
    stream_input = proc.stdout,
    stream_output = proc.stdin
  })

  client.notifications:subscribe(function(notif)
    vim.show(notif)
  end)

  local fname = P(vim.call.expand("%:p"))
  local flowconfig = find_nearest(fname.parent, '.flowconfig')

  vim.show(flowconfig.string)

  local initialized = client:request("initialize", {
    processId = uv._uv.getpid(),
    rootUri = 'file://' .. flowconfig.string,
    capabilities = capabilities,
  }):wait()

  vim.show(initialized)
end).completed:subscribe(function()
  -- vim.api.nvim_command('DONE')
end)
