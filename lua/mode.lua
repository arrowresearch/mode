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

local function find_closest(curr, fname)
  local stat, err = uv._uv.fs_stat((curr / fname).string)
  if stat ~= nil then
    return curr
  else
    local next = path.parent(cur)
    if next == nil then
      return nil
    else
      return find_closest(next, fname)
    end
  end
end

-- Quickfix

local Quickfix = {}

function Quickfix.set(list)
  vim.call.setqflist(list, 'r')
end

-- LSP

local LSP = {
  _by_root = {}
}

function LSP:start(id, root, config)
  -- check if we have client running for the id
  local client = self._by_root[id]
  if client then
    return
  end

  local proc = uv.Process:new({
    cmd = config.cmd,
    args = config.args
  })

  self._by_root[id] = {
    shutdown = function()
      proc:shutdown()
    end
  }

  local client = jsonrpc.JSONRPCClient:new({
    stream_input = proc.stdout,
    stream_output = proc.stdin
  })

  client.notifications:subscribe(function(notif)
    vim.show(notif)
  end)

  Task:new(function()
    local initialized = client:request("initialize", {
      processId = uv._uv.getpid(),
      rootUri = 'file://' .. root.string,
      capabilities = capabilities,
    }):wait()

    vim.show(initialized)
  end)
end

function LSP:shutdown(id)
  local client = self._by_root[id]
  assert(client, 'LSP.shutdown: unable to find server')
  client.shutdown()
end

function LSP:shutdown_all()
  for _idx, client in pairs(self._by_root) do
    client.shutdown()
  end
end

-- An example config for flow
local flow_config = {
  cmd = './node_modules/.bin/flow',
  args = {'lsp'},
  find_root = function(filename)
    return find_closest(filename.parent, '.flowconfig')
  end
}

vim.autocommand.register {
  event = {vim.autocommand.BufRead, vim.autocommand.BufNewFile},
  pattern = '*.js',
  action = function()
    local config = flow_config
    local filename = P(vim.call.expand("%:p"))
    local root = config.find_root(filename)
    assert(root, 'Unable to find root')
    local id = root.string
    LSP:start(id, root, config)
  end
}

vim.autocommand.register {
  event = vim.autocommand.VimLeavePre,
  pattern = '*',
  action = function()
    LSP:shutdown_all()
  end
}
