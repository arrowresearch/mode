local util = require 'mode.util'
local uv = require 'mode.uv'
local jsonrpc = require 'mode.jsonrpc'
local Position = require 'mode.position'
local diagnostics = require 'mode.diagnostics'
local vim = require 'mode.vim'
local path = require 'mode.path'
local P = path.split

local TextDocumentPosition = util.Object:extend()

function TextDocumentPosition:init(o)
  self.textDocument = {uri = o.uri}
  self.position = Position:new {
    line = o.line,
    character = o.character,
  }
end

function TextDocumentPosition.__eq(a, b)
  return a.textDocument.uri == b.textDocument.uri and a.position == b.position
end

local LSPUtil = {}

function LSPUtil.uri_of_path(p)
  return "file://" .. p.string
end

function LSPUtil.uri_to_path(uri)
  -- strips file:// prefix
  return P(string.sub(uri, 8))
end

function LSPUtil.current_text_document_position()
  local pos = vim.call.getpos('.')
  local lnum = pos[2]
  local col = pos[3]
  local filename = P(vim._vim.api.nvim_buf_get_name(0))
  local uri = LSPUtil.uri_of_path(filename)
  return TextDocumentPosition:new {
    uri = uri,
    line = lnum - 1,
    character = col - 1,
  }
end

local LSPClient = util.Object:extend()

function LSPClient:init(o)
  self.seen = false
  self.jsonrpc = o.jsonrpc
  self.root = o.root
  self.languageId = o.languageId
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
    rootUri = LSPUtil.uri_of_path(self.root),
    capabilities = self.capabilities,
  }):map(function(reply)
    self.is_utf8 = reply.result.offsetEncoding == "utf-8"
    return reply
  end)

  self.jsonrpc.notifications:subscribe(function(notif)
    if notif.method == 'textDocument/publishDiagnostics' then
      local filename = LSPUtil.uri_to_path(notif.params.uri)
      local items = {}
      for _, diag in ipairs(notif.params.diagnostics) do
        diag.relatedInformation = nil
        diag.relatedLocations = nil
        table.insert(items, {
          filename = filename,
          range = diag.range,
	        message = diag.message,
	      })
      end
      diagnostics:set(filename, items)
      if not self.is_insert_mode then
        diagnostics:update()
      end
    else
      vim.show(notif)
    end
  end)
end

function LSPClient:did_open(bufnr)
  if self.seen then return end
  self.seen = true
  self.initialized:wait()
  local uri = LSPUtil.uri_of_path(P(vim._vim.api.nvim_buf_get_name(bufnr)))
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
      languageId = self.languageId,
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
      uri = LSPUtil.uri_of_path(P(vim._vim.api.nvim_buf_get_name(bufnr))),
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
  diagnostics:update()
end

function LSPClient:shutdown()
  self.jsonrpc:request("shutdown", nil)
  self.jsonrpc:notify("exit", nil)
  self.jsonrpc:stop()
end

local LSP = {
  LSPClient = LSPClient,
  LSPUtil = LSPUtil,
  _by_root = {},
  _config_by_filetype = {},
}

function LSP:configure(config)
  local filetypes
  if util.table_is_array(config.filetype) then
    filetypes = config.filetype
  else
    filetypes = {config.filetype}
  end
  for _, filetype in ipairs(filetypes) do
    self._config_by_filetype[filetype] = config
  end
end

function LSP:start(id, config)
  -- check if we have client running for the id
  local lsp = self._by_root[id]
  if lsp then
    return lsp.client
  end

  local proc = uv.Process:new({
    cmd = config.cmd,
    args = config.args
  })

  local client = self.LSPClient:new({
    root = config.root,
    languageId = config.languageId,
    jsonrpc = jsonrpc.JSONRPCClient:new({
      stream_input = proc.stdout,
      stream_output = proc.stdin
    })
  })

  -- vim.show("LSP started")

  self._by_root[id] = {client = client, proc = proc}

  return client
end

function LSP:get_for_current_buffer()
  local filetype = vim._vim.api.nvim_buf_get_option(0, 'filetype')
  local config = self._config_by_filetype[filetype]
  if not config then
    return
  end
  local filename = P(vim.call.expand("%:p"))
  local root = config.root(filename)
  if not root then
    return
  end
  local cmd, args = config.command(root)
  local id = root.string
  return self:start(id, {
    languageId = config.languageId,
    root = root,
    cmd = cmd,
    args = args
  })
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

return LSP
