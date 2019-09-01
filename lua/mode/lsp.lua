local util = require 'mode.util'
local uv = require 'mode.uv'
local async = require 'mode.async'
local jsonrpc = require 'mode.jsonrpc'
local Position = require 'mode.position'
local diagnostics = require 'mode.diagnostics'
local vim = require 'mode.vim'
local path = require 'mode.path'
local BufferWatcher = require 'mode.buffer_watcher'
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

local function uri_of_path(p)
  return "file://" .. p.string
end

local function uri_to_path(uri)
  -- strips file:// prefix
  return P(string.sub(uri, 8))
end

local function current_text_document_position()
  local pos = vim.call.getpos('.')
  local lnum = pos[2]
  local col = pos[3]
  local filename = vim.Buffer:current():filename()
  local uri = uri_of_path(filename)
  return TextDocumentPosition:new {
    uri = uri,
    line = lnum - 1,
    character = col - 1,
  }
end

local LSPClient = util.Object:extend()

LSPClient.type = "lsp"

function LSPClient:init(o)
  self.jsonrpc = o.jsonrpc
  self.root = o.root
  self.languageId = o.languageId

  self.buffers = {}
  self.is_insert_mode = false
  self.is_utf8 = nil

  self.on_shutdown = async.Channel:new()

  self.capabilities = {
    textDocument = {
      publishDiagnostics = true,
    },
    offsetEncoding = {'utf-8', 'utf-16'},
  }
  self.initialized = self.jsonrpc:request("initialize", {
    processId = uv._uv.getpid(),
    rootUri = uri_of_path(self.root),
    capabilities = self.capabilities,
  }):map(function(reply)
    self.is_utf8 = reply.result.offsetEncoding == "utf-8"
    return reply
  end)

  self.jsonrpc.notifications:subscribe(function(notif)
    if notif.method == 'textDocument/publishDiagnostics' then
      local filename = uri_to_path(notif.params.uri)
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

function LSPClient:did_open(buffer)
  self.initialized:wait()
  local uri = uri_of_path(buffer:filename())
  local lines = buffer:contents_lines()
  local text = table.concat(lines, "\n")
  if buffer.options.eol then
    text = text..'\n'
  end
  self.jsonrpc:notify("textDocument/didOpen", {
    textDocument = {
      uri = uri,
      text = text,
      version = buffer:changedtick(),
      languageId = self.languageId,
    }
  })
  local watcher = BufferWatcher:new {
    buffer = buffer,
    is_utf8 = self.is_utf8,
  }
  watcher.updates:subscribe(function(change)
    self:did_change(change)
  end)
  self.buffers[buffer.id] = { watcher = watcher, buffer = buffer }
end

function LSPClient:did_close(buffer)
  local record = self.buffers[buffer.id]
  if record then
    record.watcher:shutdown()
  end
  local uri = uri_of_path(buffer:filename())
  self.jsonrpc:notify("textDocument/didClose", {
    textDocument = { uri = uri }
  })
end

function LSPClient:did_change(change)
  self.initialized:wait()
  local lines = change.buffer:contents_lines(change.start, change.stopped)
  local text = table.concat(lines, "\n") .. ((change.stopped > change.start) and "\n" or "")
  local length = (self.is_utf8 and change.bytes) or change.units
  self.jsonrpc:notify("textDocument/didChange", {
    textDocument = {
      uri = uri_of_path(change.buffer:filename()),
      version = change.tick
    },
    contentChanges = {
      {
        range = {
          start = {
            line = change.start,
            character = 0
          },
          ["end"] = {
            line = change.stop,
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

function LSPClient.did_buffer_enter(_) end

function LSPClient:start(config)
  -- check if we have client running for the id
  local proc = uv.Process:new {
    cmd = config.cmd,
    args = config.args
  }

  local client = self:new {
    root = config.root,
    languageId = config.languageId,
    jsonrpc = jsonrpc.JSONRPCClient:new {
      stream_input = proc.stdout,
      stream_output = proc.stdin
    }
  }

  client.on_shutdown:subscribe(function()
    proc:shutdown()
  end)

  return client
end


function LSPClient:shutdown()
  self.jsonrpc:request("shutdown", nil)
  self.jsonrpc:notify("exit", nil)
  self.jsonrpc:stop()
  self.on_shutdown:put(true)
end

return {
  LSPClient = LSPClient,
  current_text_document_position = current_text_document_position,
  uri_of_path = uri_of_path,
  uri_to_path = uri_to_path,
}
