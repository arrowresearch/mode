-- luacheck: globals vim string

local util = require 'mode.util'
local path = require 'mode.path'
local vim = require 'mode.vim'
local async = require 'mode.async'
local jsonrpc = require 'mode.jsonrpc'
local uv = require 'mode.uv'
local P = path.split

local function report_error(msg, ...)
  msg = string.format(msg, ...)
  print("ERROR: " .. msg)
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
    0, self.name, self.name, sign.buffer,
    {lnum = sign.line + 1, priority = sign.priority or 100}
  )
  assert(res ~= -1, 'Signs.place: unable to place sign')
end

function Signs:unplace_all()
  local res = vim.call.sign_unplace(self.name)
  assert(res == 0, 'Signs.unplace_all: Unable to unplace all signs')
end

-- Highlights

local Highlights = util.Object:extend()

function Highlights:init(o)
  self.namespace = vim._vim.api.nvim_create_namespace(o.name or '')
end

function Highlights:add(item)
  if item.buffer == -1 then
    return
  end
  local start, stop = item.range.start, item.range['end']
  if start.line == stop.line then
    vim._vim.api.nvim_buf_add_highlight(
      item.buffer, self.namespace, item.hlgroup,
      start.line, start.character, stop.character
    )
  else
    for line = start.line, stop.line do
      if line == start.line then
        vim._vim.api.nvim_buf_add_highlight(
          item.buffer, self.namespace, item.hlgroup,
          line, start.character, -1
        )
      elseif line == stop.line then
        vim._vim.api.nvim_buf_add_highlight(
          item.buffer, self.namespace, item.hlgroup,
          line, 0, stop.character
        )
      else
        vim._vim.api.nvim_buf_add_highlight(
          item.buffer, self.namespace, item.hlgroup,
          line, 0, -1
        )
      end
    end
  end
end

function Highlights:clear(buffer)
  if buffer == -1 then
    return
  end
  vim._vim.api.nvim_buf_clear_namespace(buffer, self.namespace, 0, -1)
end

-- Diagnostics

local Diagnostics = {
  use_quickfix_list = true,
  use_highlights = Highlights:new {
    name = 'mode-diag-hightlights'
  },
  use_signs = Signs:new {
    name = 'mode-diag',
    text = '✖',
    texthl = 'Error',
  },
  updated = false,
  by_filename = {}
}

function Diagnostics:get(filename)
  return self.by_filename[filename.string] or {}
end

function Diagnostics:set(filename, items)
  items = items or {}
  items = util.array_copy(items)
  table.sort(items, function(a, b)
    if a.range.start.line < b.range.start.line then
      return true
    elseif
      a.range.start.line == b.range.start.line
      and a.range.start.character < b.range.start.character
    then
      return true
    else
      return false
    end
  end)
  self.by_filename[filename.string] = items
  self.updated = false
end

function Diagnostics:update_for_buffer(buffer)
  local items = self.by_filename[vim._vim.api.nvim_buf_get_name(buffer)] or {}
  if self.use_highlights then
    self.use_highlights:clear(buffer)
  end
  for _, item in ipairs(items) do
    if self.use_highlights then
      self.use_highlights:add {
        hlgroup = 'ModeError',
        buffer = buffer,
        range = item.range,
      }
    end
    if self.use_signs then
      self.use_signs:place {
        buffer = buffer,
        line = item.range.start.line,
      }
    end
  end
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

  local qf = {}

  for filename, items in pairs(self.by_filename) do
    local buffer = vim.call.bufnr(filename)
    local buffer_loaded = buffer ~= -1

    if self.use_highlights then
      self.use_highlights:clear(buffer)
    end

    for _, item in ipairs(items) do
      if self.use_signs and buffer_loaded then
        self.use_signs:place {
          buffer = buffer,
          line = item.range.start.line,
        }
      end
      if self.use_highlights and buffer_loaded then
        self.use_highlights:add {
          hlgroup = 'ModeError',
          buffer = buffer,
          range = item.range,
        }
      end
      table.insert(qf, {
        filename = item.filename.string,
        lnum = item.range.start.line + 1,
        col = item.range.start.character + 1,
        text = item.message,
        type = 'E',
      })
    end
  end
  if self.use_quickfix_list then
    vim.call.setqflist(qf, 'r')
  end
  self.updated = true
end

-- LSP

local Position = util.Object:extend()

function Position:init(o)
  self.line = o.line
  self.character = o.character
end

function Position.__eq(a, b)
  return a.line == b.line and a.character == b.character
end

function Position.__lt(a, b)
  if a.line < b.line then
    return true
  elseif a.line == b.line and a.character < b.character then
    return true
  else
    return false
  end
end

function Position.__le(a, b)
  return a == b or a < b
end

function Position:current()
  local p = vim.call.getpos('.')
  return self:new {
    line = p[2] - 1,
    character = p[3] - 1,
  }
end

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
  Diagnostics:update()
end

function LSPClient:shutdown()
  self.jsonrpc:request("shutdown", nil)
  self.jsonrpc:notify("exit", nil)
  self.jsonrpc:stop()
end

local LSP = {
  _by_root = {},
}

function LSP:start(id, root, config)
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

local flow_config = {
  cmd = './node_modules/.bin/flow',
  languageId = 'javascript',
  args = {'lsp'},
  find_root = function(filename)
    return find_closest(filename.parent, '.flowconfig')
  end
}

local merlin_config = {
  cmd = 'esy',
  languageId = 'ocaml',
  args = {
    'exec-command',
    '--include-build-env',
    '--include-current-env',
    '/Users/andreypopp/Workspace/esy-ocaml/merlin/ocamlmerlin-lsp'
  },
  find_root = function(filename)
    return find_closest(filename.parent, 'package.json')
  end
}

local config_by_filetype = {
  javascript = flow_config,
  ['javascript.jsx'] = flow_config,
  ocaml = merlin_config,
  reason = merlin_config,
}

local function get_lsp_client_for_this_buffer()
  local filetype = vim._vim.api.nvim_buf_get_option(0, 'filetype')
  local config = config_by_filetype[filetype]
  if not config then
    return
  end
  local filename = P(vim.call.expand("%:p"))
  local root = config.find_root(filename)
  if not root then
    return
  end
  local id = root.string
  return LSP:start(id, root, config)
end

local function definition()
  async.task(function()
    local lsp = get_lsp_client_for_this_buffer()
    if not lsp then
      report_error "no LSP found for this buffer"
      return
    end

    local params = LSPUtil.current_text_document_position()
    local resp = lsp.jsonrpc:request("textDocument/definition", params):wait()
    if not resp.result or #resp.result == 0 then
      return
    end

    local pos = resp.result[1]
    local uri = pos.uri
    local filename = LSPUtil.uri_to_path(pos.uri)

    if uri ~= params.textDocument.uri then
      vim.execute([[edit %s]], filename.string)
    end

    local lnum = pos.range.start.line + 1
    local col = pos.range.start.character + 1
    vim.call.cursor(lnum, col)
  end)
end

local Modal = {
  win = nil,
}

function Modal:open(message)
  self:close()
  local win = vim.call.win_getid()
  local width = vim._vim.api.nvim_win_get_width(win)
  local height = vim._vim.api.nvim_win_get_height(win)
  local size = 4
  local buf = vim._vim.api.nvim_create_buf(false, true)
  vim._vim.api.nvim_buf_set_lines(buf, 0, -1, false, { message })
  self.win = vim._vim.api.nvim_open_win(buf, false, {
    relative = 'win',
    style = 'minimal',
    height = size,
    width = width,
    row = height - size + 1,
    col = 0,
  })
end

function Modal:close()
  if self.win then
    vim._vim.api.nvim_win_close(self.win, true)
    self.win = nil
  end
end

local function hover()
  async.task(function()
    local lsp = get_lsp_client_for_this_buffer()
    if not lsp then
      report_error "no LSP found for this buffer"
      return
    end

    local pos = LSPUtil.current_text_document_position()
    local resp = lsp.jsonrpc:request("textDocument/hover", pos):wait()

    -- Check that we are at the same position
    local next_pos = LSPUtil.current_text_document_position()
    if next_pos ~= pos then
      return
    end

    local message
    if not resp.result then
      message = "<no response>"
    else
      local contents = resp.result.contents
      if util.table_is_array(contents) then
        local parts = {}
        for _, item in ipairs(contents) do
          table.insert(parts, item.value)
        end
        message = table.concat(parts, '\n')
      else
        message = contents.value
      end
    end
    Modal:open(message)
  end)
end

local function prev_diagnostic_location(o)
  o = o or {wrap = true}
  local filename = P(vim._vim.api.nvim_buf_get_name(0))
  local items = Diagnostics:get(filename)
  local cur = Position:current()
  local found = nil
  for i = #items, 1, -1 do
    local start = items[i].range.start
    if
        start.line < cur.line
        or start.line == cur.line and start.character < cur.character
    then
      found = start
      break
    end
  end
  if not found and o.wrap and #items > 0 then
    found = items[#items].range.start
  end
  if found then
    vim.call.cursor(found.line + 1, found.character + 1)
  end
end

local function next_diagnostic_location(o)
  o = o or {wrap = true}
  local filename = P(vim._vim.api.nvim_buf_get_name(0))
  local cur = Position:current()
  local items = Diagnostics:get(filename)
  local found = nil
  for i = 1, #items do
    local start = items[i].range.start
    if
        start.line > cur.line
        or start.line == cur.line and start.character > cur.character
    then
      found = start
      break
    end
  end
  if not found and o.wrap and #items > 0 then
    found = items[1].range.start
  end
  if found then
    vim.call.cursor(found.line + 1, found.character + 1)
  end
end

vim.autocommand.register {
  event = vim.autocommand.FileType,
  pattern = '*',
  action = function()
    async.task(function()
      local buffer = vim.call.bufnr('%')
      local client = get_lsp_client_for_this_buffer()
      if client then
        client:did_open(buffer)
      end
      Diagnostics:update_for_buffer(buffer)
    end)
  end
}

vim.autocommand.register {
  event = vim.autocommand.InsertEnter,
  pattern = '*',
  action = function()
    local client = get_lsp_client_for_this_buffer()
    if client then
      client:did_insert_enter(vim.call.bufnr('%'))
    end
  end
}

vim.autocommand.register {
  event = vim.autocommand.InsertLeave,
  pattern = '*',
  action = function()
    local client = get_lsp_client_for_this_buffer()
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

vim.autocommand.register {
  event = {vim.autocommand.CursorMoved, vim.autocommand.CursorMovedI},
  pattern = '*',
  action = function()
    async.task(function()
      Modal:close()
    end)
  end
}

return {
  LSP = LSP,
  Diagnostics = Diagnostics,
  definition = definition,
  hover = hover,
  next_diagnostic_location = next_diagnostic_location,
  prev_diagnostic_location = prev_diagnostic_location,
}
