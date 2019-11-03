local util = require 'mode.util'
local logging = require 'mode.logging'
local uv = require 'mode.uv'
local async = require 'mode.async'
local jsonrpc = require 'mode.jsonrpc'
local Position = require 'mode.position'
local diagnostics = require 'mode.diagnostics'
local vim = require 'mode.vim'
local path = require 'mode.path'
local BufferWatcher = require 'mode.buffer_watcher'
local P = path.split

-- Utils

local function uri_of_path(p)
  return "file://" .. p.string
end

local function uri_to_path(uri)
  -- strips file:// prefix
  return P(string.sub(uri, 8))
end

-- TextDocumentPosition

local TextDocumentPosition = util.Object:extend()

function TextDocumentPosition:init(o)
  self.textDocument = {uri = o.uri}
  self.position = o.position
end

function TextDocumentPosition.__eq(a, b)
  return a.textDocument.uri == b.textDocument.uri and a.position == b.position
end

function TextDocumentPosition:current()
  local buf = vim.Buffer:current()
  return self:new {
    uri = uri_of_path(buf:filename()),
    position = Position:current(),
  }
end

local LSPClient = util.Object:extend()

LSPClient.type = "lsp"

function LSPClient:init(o)
  self.log = logging.get_logger(string.format("lsp:%s", o.id))
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
      self.log:info("textDocument/publishDiagnostics %s %d", filename, #notif.params.diagnostics)
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
  async.task(function()
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
    self.buffers[buffer.id] = {
      watcher = watcher,
      buffer = buffer,
      changedtick = buffer:changedtick(),
      content_changes = {},
      content_changes_paused = false,
      content_changes_cancel_timer = nil,
    }
    watcher.updates:subscribe(function(change)
      self:did_change(change)
    end)
  end)
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
  local buf = change.buffer
  local info = self.buffers[buf.id]
  if not info or info.content_changes_paused then
    return
  end
  self.initialized:wait()
  local lines = buf:contents_lines(change.start, change.stopped)
  local text = table.concat(lines, "\n") .. ((change.stopped > change.start) and "\n" or "")
  local length = (self.is_utf8 and change.bytes) or change.units
  local content_change = {
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
  table.insert(self.buffers[buf.id].content_changes, content_change)
  self:schedule_flush_did_change(buf)
end

function LSPClient:schedule_flush_did_change(buf)
  local info = self.buffers[buf.id]
  if info.content_changes_cancel_timer ~= nil then
    info.content_changes_cancel_timer()
    info.content_changes_cancel_timer = nil
  end
  local delay, cancel = uv.sleep(700)
  info.content_changes_cancel_timer = cancel
  async.task(function()
    local ok = delay:wait()
    info.content_changes_cancel_timer = nil
    if ok then
      vim.wait()
      self:flush_did_change(buf)
    end
  end)
end

function LSPClient:force_flush_did_change(buf)
  local info = self.buffers[buf.id]
  if info.content_changes_cancel_timer ~= nil then
    info.content_changes_cancel_timer()
    info.content_changes_cancel_timer = nil
    self:flush_did_change(buf)
  end
end

function LSPClient:flush_did_change(buf)
  if not buf:exists() then
    return
  end
  local info = self.buffers[buf.id]
  local content_changes = info.content_changes
  if #content_changes == 0 then
    return
  end
  info.content_changes = {}
  self.jsonrpc:notify("textDocument/didChange", {
    textDocument = {
      uri = uri_of_path(buf:filename()),
      version = info.changedtick,
    },
    contentChanges = content_changes,
  })
end

function LSPClient:pause_did_change(buf)
  local info = self.buffers[buf.id]
  if info then
    info.content_changes_paused = true
  end
end

function LSPClient:resume_did_change(buf)
  local info = self.buffers[buf.id]
  if not info or not info.content_changes_paused then
    return
  end
  info.content_changes_paused = false
  -- Send whole doc update
  local lines = buf:contents_lines()
  local text = table.concat(lines, "\n") .. "\n"
  self.jsonrpc:notify("textDocument/didChange", {
    textDocument = {
      uri = uri_of_path(buf:filename()),
      version = buf.vars.changedtick
    },
    contentChanges = {
      {
        text = text,
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
  local proc = uv.spawn {
    cmd = config.cmd,
    args = config.args
  }

  local client = self:new {
    id = config.id,
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
  TextDocumentPosition = TextDocumentPosition,
  uri_of_path = uri_of_path,
  uri_to_path = uri_to_path,
}
