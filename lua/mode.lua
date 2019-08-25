-- luacheck: globals vim

local util = require 'mode.util'
local path = require 'mode.path'
local vim = require 'mode.vim'
local async = require 'mode.async'
local jsonrpc = require 'mode.jsonrpc'
local uv = require 'mode.uv'
local P = path.split

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
  updated = false,
  by_filename = {}
}

function Diagnostics:set(filename, items)
  self.by_filename[filename.string] = items
  self.updated = false
end

function Diagnostics:update()
  if self.updated then
    return
  end
  -- TODO(andreypopp): set signs per file
  if self.use_signs then
    self.use_signs:unplace_all()
  end
  if self.use_quickfix_list then
    vim.call.setqflist({}, 'r')
  end
  for filename, items in pairs(self.by_filename) do
    vim.show("diag: " .. filename .. " len: " .. tostring(#items))
    if self.use_quickfix_list then
      vim.call.setqflist(items, 'a')
    end
    if self.use_signs then
      for _, item in ipairs(items) do
        self.use_signs:place({expr = item.filename, lnum = item.lnum})
      end
    end
  end
  self.updated = true
end

-- LSP

local LSP = {
  _by_root = {},

}

function LSP.uri_of_path(p)
  return "file://" .. p.string
end

function LSP.uri_to_path(uri)
  -- strips file:// prefix
  return P(string.sub(uri, 8))
end

local LSPClient = util.Object:extend()

function LSPClient:init(o)
  self.jsonrpc = o.jsonrpc
  self.root = o.root
  self.is_insert_mode = false
  self.is_utf8 = nil
  self.capabilities = {
    textDocument = {
      publishDiagnostics = true,
    },
    offsetEncoding = {'utf-8', 'utf-16'},
  }
  self.initialized = self.jsonrpc:request("initialize", {
    processId = uv._uv.getpid(),
    rootUri = LSP.uri_of_path(self.root),
    capabilities = self.capabilities,
  }):map(function(reply)
    self.is_utf8 = reply.result.offsetEncoding == "utf-8"
    return reply
  end)

  self.jsonrpc.notifications:subscribe(function(notif)
    if notif.method == 'textDocument/publishDiagnostics' then
      local filename = LSP.uri_to_path(notif.params.uri)
      local items = {}
      for _, diag in ipairs(notif.params.diagnostics) do
        diag.relatedInformation = nil
        diag.relatedLocations = nil
        table.insert(items, {
          filename = filename.string,
	        lnum = diag.range.start.line + 1,
	        col = diag.range.start.character + 1,
	        text = diag.message,
	        type = 'E',
	      })
      end
      Diagnostics:set(filename, items)
      if not self.is_insert_mode then
        Diagnostics:update()
      end
    else
      vim.show(notif)
    end
  end)
end

function LSPClient:did_open(bufnr)
  self.initialized:wait()
  local uri = LSP.uri_of_path(P(vim._vim.api.nvim_buf_get_name(bufnr)))
  local lines = vim._vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local text = table.concat(lines, "\n")
  if vim._vim.api.nvim_buf_get_option(bufnr, 'eol') then
    text = text..'\n'
  end
  self.jsonrpc:notify("textDocument/didOpen", {
    textDocument = {
      uri = uri,
      text = text,
      version = vim._vim.api.nvim_buf_get_changedtick(bufnr),
      -- languageId = luvlsp.config.lsp_languageId
    }
  })
  vim._vim.api.nvim_buf_attach(bufnr, false, {
    on_lines=function(...) self:did_change(...) end,
    utf_sizes=not self.is_utf8
  })
end

function LSPClient:did_change(_, bufnr, tick, start, stop, stopped, bytes, _, units)
  self.initialized:wait()
  local lines = vim._vim.api.nvim_buf_get_lines(bufnr, start, stopped, true)
  local text = table.concat(lines, "\n") .. ((stopped > start) and "\n" or "")
  local length = (self.is_utf8 and bytes) or units
  self.jsonrpc:notify("textDocument/didChange", {
    textDocument = {
      uri = LSP.uri_of_path(P(vim._vim.api.nvim_buf_get_name(bufnr))),
      version = tick
    },
    contentChanges = {
      {
        range = {
          start = {
            line = start,
            character = 0
          },
          ["end"] = {
            line = stop,
            character = 0
          }
        },
        text = text,
        rangeLength = length
      }
    }
  })
end

function LSPClient:did_insert_enter(_)
  self.is_insert_mode = true
end

function LSPClient:did_insert_leave(_)
  self.is_insert_mode = false
  Diagnostics:update()
end

function LSPClient:shutdown()
  self.jsonrpc:request("shutdown", nil):wait()
  self.jsonrpc:notify("exit", nil)
  self.jsonrpc:stop()
end

function LSP:get(id, root, config)
  -- check if we have client running for the id
  local lsp = self._by_root[id]
  if lsp then
    return lsp.client
  end

  local proc = uv.Process:new({
    cmd = config.cmd,
    args = config.args
  })

  local client = LSPClient:new({
    root = root,
    jsonrpc = jsonrpc.JSONRPCClient:new({
      stream_input = proc.stdout,
      stream_output = proc.stdin
    })
  })

  self._by_root[id] = {client = client, proc = proc}

  return client
end

function LSP:shutdown(id)
  local lsp = self._by_root[id]
  self._by_root[id] = nil
  assert(lsp, 'LSP.shutdown: unable to find server')
  lsp.client:shutdown()
  lsp.proc:shutdown()
end

function LSP:shutdown_all()
  for id, _ in pairs(self._by_root) do
    self:shutdown(id)
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

local function client_for_current_buffer()
  local config = flow_config
  local filename = P(vim.call.expand("%:p"))

  local root = config.find_root(filename)
  if not root then
    return
  end

  local id = root.string
  return LSP:get(id, root, config)
end

vim.autocommand.register {
  event = vim.autocommand.FileType,
  pattern = 'javascript',
  action = function()
    async.task(function()
      local client = client_for_current_buffer()
      if client then
        client:did_open(vim.call.bufnr('%'))
      end
    end)
  end
}

vim.autocommand.register {
  event = vim.autocommand.InsertEnter,
  pattern = '*',
  action = function()
    local client = client_for_current_buffer()
    if client then
      client:did_insert_enter(vim.call.bufnr('%'))
    end
  end
}

vim.autocommand.register {
  event = vim.autocommand.InsertLeave,
  pattern = '*',
  action = function()
    local client = client_for_current_buffer()
    if client then
      client:did_insert_leave(vim.call.bufnr('%'))
    end
  end
}

vim.autocommand.register {
  event = vim.autocommand.VimLeavePre,
  pattern = '*',
  action = function()
    async.task(function()
      LSP:shutdown_all()
    end)
  end
}

return {
  LSP = LSP,
  Diagnostics = Diagnostics,
}
