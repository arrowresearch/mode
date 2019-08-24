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

local function find_closest(curr, fname)
  local stat, _ = uv._uv.fs_stat((curr / fname).string)
  if stat ~= nil then
    return curr
  else
    local next = curr.parent
    if next == nil then
      return nil
    else
      return find_closest(next, fname)
    end
  end
end

-- Signs

local Signs = util.Object:extend()

function Signs:init(o)
  self.name = o.name
  local res = vim.call.sign_define(self.name, {
    text = o.text,
    texthl = o.texthl,
    linehl = o.linehl,
    numhl = o.numhl,
  })
  assert(res == 0, 'Signs.init: unable to define sign')
end

function Signs:place(sign)
  local res = vim.call.sign_place(
    0, self.name, self.name, sign.expr, {lnum = sign.lnum}
  )
  assert(res ~= -1, 'Signs.place: unable to place sign')
end

function Signs:unplace_all()
  local res = vim.call.sign_unplace(self.name)
  assert(res == 0, 'Signs.unplace_all: Unable to unplace all signs')
end

-- Diagnostics

local Diagnostics = {
  use_quickfix_list = true,
  use_signs = Signs:new({
    name = 'mode-diag',
    text = '✖',
    texthl = 'Error',
  }),
  items = {}
}

function Diagnostics:set(items)
  self.items = items
  if self.use_quickfix_list then
    vim.call.setqflist(items, 'r')
  end
  if self.use_signs then
    self.use_signs:unplace_all()
    for _, item in ipairs(items) do
      self.use_signs:place({expr = item.filename, lnum = item.lnum})
    end
  end
end

-- LSP

local LSP = {
  _by_root = {},

  capabilities = {
    textDocument = {
      publishDiagnostics = true,
    },
    offsetEncoding = {'utf-8', 'utf-16'},
  },
}

function LSP.uri_of_path(p)
  return "file://" .. p.string
end

function LSP.uri_to_path(uri)
  -- strips file:// prefix
  return P(string.sub(uri, 8))
end

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

  local jsonrpc_client = jsonrpc.JSONRPCClient:new({
    stream_input = proc.stdout,
    stream_output = proc.stdin
  })

  self._by_root[id] = {
    shutdown = function()
      proc:shutdown()
      jsonrpc_client:stop()
    end
  }

  jsonrpc_client.notifications:subscribe(function(notif)
    if notif.method == 'textDocument/publishDiagnostics' then
      local filename = self.uri_to_path(notif.params.uri)
      local items = {}
      for _, diag in ipairs(notif.params.diagnostics) do
        table.insert(items, {
          filename = filename.string,
	        lnum = diag.range.start.line + 1,
	        col = diag.range.start.character + 1,
	        text = diag.message,
	        type = 'E',
	      })
      end
      Diagnostics:set(items)
    else
      vim.show(notif)
    end
  end)

  Task:new(function()
    jsonrpc_client:request("initialize", {
      processId = uv._uv.getpid(),
      rootUri = self.uri_of_path(root),
      capabilities = self.capabilities,
    }):wait()
  end)
end

function LSP:shutdown(id)
  local client = self._by_root[id]
  assert(client, 'LSP.shutdown: unable to find server')
  client.shutdown()
end

function LSP:shutdown_all()
  for _, client in pairs(self._by_root) do
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
    if not root then
      return
    end

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
