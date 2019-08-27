-- luacheck: globals vim string

local util = require 'mode.util'
local path = require 'mode.path'
local vim = require 'mode.vim'
local async = require 'mode.async'
local diagnostics = require 'mode.diagnostics'
local LSP = require 'mode.lsp'
local Position = require 'mode.position'
local modal = require 'mode.modal'
local fs = require 'mode.fs'
local P = path.split

local function report_error(msg, ...)
  msg = string.format(msg, ...)
  print("ERROR: " .. msg)
end

LSP:configure {
  filetype = {'javascript', 'javascript.jsx'},
  languageId = 'javascript',
  command = function(root)
    local cmd = root / 'node_modules/.bin/flow'
    local args = {'lsp'}
    return cmd, args
  end,
  root = function(filename)
    return fs.find_closest_ancestor(filename.parent, function(p)
      return fs.exists(p / '.flowconfig')
    end)
  end
}

LSP:configure {
  languageId = 'ocaml',
  filetype = {'ocaml', 'reason'},
  command = function(_)
    local cmd = 'esy'
    local args = {
      'exec-command',
      '--include-build-env',
      '--include-current-env',
      '/Users/andreypopp/Workspace/esy-ocaml/merlin/ocamlmerlin-lsp'
    }
    return cmd, args
  end,
  root = function(filename)
    return fs.find_closest_ancestor(filename.parent, function(p)
      return fs.exists(p / 'esy.json') or fs.exists(p / 'package.json')
    end)
  end
}

local function definition()
  async.task(function()
    local lsp = LSP:get_for_current_buffer()
    if not lsp then
      report_error "no LSP found for this buffer"
      return
    end

    local params = LSP.LSPUtil.current_text_document_position()
    local resp = lsp.jsonrpc:request("textDocument/definition", params):wait()
    if not resp.result or #resp.result == 0 then
      return
    end

    local pos = resp.result[1]
    local uri = pos.uri
    local filename = LSP.LSPUtil.uri_to_path(pos.uri)

    if uri ~= params.textDocument.uri then
      vim.execute([[edit %s]], filename.string)
    end

    local lnum = pos.range.start.line + 1
    local col = pos.range.start.character + 1
    vim.call.cursor(lnum, col)
  end)
end

local function type_definition()
  async.task(function()
    local lsp = LSP:get_for_current_buffer()
    if not lsp then
      report_error "no LSP found for this buffer"
      return
    end

    local params = LSP.LSPUtil.current_text_document_position()
    local resp = lsp.jsonrpc:request("textDocument/typeDefinition", params):wait()
    if not resp.result or #resp.result == 0 then
      return
    end

    local pos = resp.result[1]
    local uri = pos.uri
    local filename = LSP.LSPUtil.uri_to_path(pos.uri)

    if uri ~= params.textDocument.uri then
      vim.execute([[edit %s]], filename.string)
    end

    local lnum = pos.range.start.line + 1
    local col = pos.range.start.character + 1
    vim.call.cursor(lnum, col)
  end)
end

local function hover()
  async.task(function()
    local lsp = LSP:get_for_current_buffer()
    if not lsp then
      report_error "no LSP found for this buffer"
      return
    end

    local pos = LSP.LSPUtil.current_text_document_position()
    local resp = lsp.jsonrpc:request("textDocument/hover", pos):wait()

    -- Check that we are at the same position
    local next_pos = LSP.LSPUtil.current_text_document_position()
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
    modal:open(message)
  end)
end

local function prev_diagnostic_location(o)
  o = o or {wrap = true}
  local filename = P(vim._vim.api.nvim_buf_get_name(0))
  local items = diagnostics:get(filename)
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
  local items = diagnostics:get(filename)
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

local function current_diagnostic()
  local filename = P(vim._vim.api.nvim_buf_get_name(0))
  local cur = Position:current()
  local items = diagnostics:get(filename)
  for i = 1, #items do
    local item = items[i]
    local start, stop = item.range.start, item.range['end']
    if cur.line < stop.line then
      break
    elseif
      cur.line == start.line
      and cur.character >= start.character
      or cur.line > start.line
    then
      if
        cur.line == stop.line and cur.character < stop.character
        or cur.line < stop.line
      then
        return item
      end
    end
  end
end

vim.autocommand.register {
  event = vim.autocommand.FileType,
  pattern = '*',
  action = function()
    async.task(function()
      local buffer = vim.call.bufnr('%')
      local client = LSP:get_for_current_buffer()
      if client then
        client:did_open(buffer)
      end
    end)
  end
}

vim.autocommand.register {
  event = vim.autocommand.InsertEnter,
  pattern = '*',
  action = function()
    local client = LSP:get_for_current_buffer()
    if client then
      client:did_insert_enter(vim.call.bufnr('%'))
    end
  end
}

vim.autocommand.register {
  event = vim.autocommand.InsertLeave,
  pattern = '*',
  action = function()
    local client = LSP:get_for_current_buffer()
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
  event = {vim.autocommand.CursorMoved},
  pattern = '*',
  action = function()
    async.task(function()
      local mode = vim._vim.api.nvim_get_mode().mode
      local diag = current_diagnostic()
      if diag and mode == 'n' then
        modal:open(diag.message)
      else
        modal:close()
      end
    end)
  end
}

return {
  definition = definition,
  type_definition = type_definition,
  hover = hover,
  next_diagnostic_location = next_diagnostic_location,
  prev_diagnostic_location = prev_diagnostic_location,
}
