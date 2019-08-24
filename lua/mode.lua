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

local LSP = {
  _by_root = {}
}

function LSP:start(id)
  -- check if we have client running for the root
  local client = self._by_root[id]
  if client then
    return
  end

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

  Task:new(function()
    local initialized = client:request("initialize", {
      processId = uv._uv.getpid(),
      rootUri = 'file://' .. id,
      capabilities = capabilities,
    }):wait()

    vim.show(initialized)
  end)

  self._by_root[id] = {
    shutdown = function()
      proc:shutdown()
    end
  }
end

function LSP:shutdown(id)
  local client = self._by_root[id]
  assert(client, 'LSP.shutdown: unable to find server')
  client.shutdown()
end

vim.autocommand.register {
  event = {vim.autocommand.BufRead, vim.autocommand.BufNewFile},
  pattern = '*.js',
  action = function()
    local filename = P(vim.call.expand("%:p"))
    local root = find_closest(filename.parent, '.flowconfig').string
    LSP:start(root)
    vim.autocommand.register {
      event = vim.autocommand.VimLeavePre,
      pattern = '*',
      action = function()
        LSP:shutdown(root)
      end
    }
  end
}
