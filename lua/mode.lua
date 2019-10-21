-- luacheck: globals vim string

local util = require 'mode.util'
local vim = require 'mode.vim'
local async = require 'mode.async'
local diagnostics = require 'mode.diagnostics'
local LanguageService = require 'mode.language_service'
local lsp = require 'mode.lsp'
local Position = require 'mode.position'
local Modal = require 'mode.modal'

local function report_error(msg, ...)
  msg = string.format(msg, ...)
  print("ERROR: " .. msg)
end

local function definition()
  async.task(function()
    local service = LanguageService:get { type = 'lsp' }
    if not service then
      report_error "no LSP found for this buffer"
      return
    end

    local params = lsp.TextDocumentPosition:current()
    local resp = service.jsonrpc:request("textDocument/definition", params):wait()
    if not resp.result or #resp.result == 0 then
      return
    end

    local pos = resp.result[1]
    local uri = pos.uri
    local filename = lsp.uri_to_path(pos.uri)

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
    local service = LanguageService:get { type = 'lsp' }
    if not service then
      report_error "no LSP found for this buffer"
      return
    end

    local params = lsp.TextDocumentPosition:current()
    local resp = service.jsonrpc:request("textDocument/typeDefinition", params):wait()
    if not resp.result or #resp.result == 0 then
      return
    end

    local pos = resp.result[1]
    local uri = pos.uri
    local filename = lsp.uri_to_path(pos.uri)

    if uri ~= params.textDocument.uri then
      vim.execute([[edit %s]], filename.string)
    end

    local lnum = pos.range.start.line + 1
    local col = pos.range.start.character + 1
    vim.call.cursor(lnum, col)
  end)
end

local function hover()
  local buffer = vim.Buffer:current()
  local pos = lsp.TextDocumentPosition:current()
  async.task(function()
    local service = LanguageService:get { type = 'lsp' }
    if not service then
      report_error "no LSP found for this buffer"
      return
    end

    local resp = service.jsonrpc:request("textDocument/hover", pos):wait()

    -- Check that we are at the same position
    local next_pos = lsp.TextDocumentPosition:current()
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
    Modal:open(buffer, message)
  end)
end

local function prev_diagnostic_location(o)
  o = o or {wrap = true}
  local filename = vim.Buffer:current():filename()
  local items = diagnostics:get(filename).items
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
  local filename = vim.Buffer:current():filename()
  local cur = Position:current()
  local items = diagnostics:get(filename).items
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

local function current_diagnostic(buffer)
  local filename = buffer:filename()
  local cur = Position:current()
  local items = diagnostics:get(filename).items
  for i = 1, #items do
    local item = items[i]
    local start, stop = item.range.start, item.range['end']
    if not stop then
      stop = {line = start.line, character = start.character + 1}
    end
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
  event = {
    vim.autocommand.CursorMoved,
    vim.autocommand.BufEnter,
    vim.autocommand.WinEnter,
  },
  pattern = '*',
  action = function(ev)
    async.task(function()
      local mode = vim._vim.api.nvim_get_mode().mode
      local diag = current_diagnostic(ev.buffer)
      if diag and mode:sub(1, 1) == 'n' then
        vim.echo(diag.message)
      else
        vim.echo('')
      end
    end)
  end
}

return {
  diagnostics_count = function()
    local filename = vim.Buffer:current():filename()
    return diagnostics:get(filename).counts
  end,
  enable_filetype = function(filetype)
    LanguageService:enable_filetype(filetype)
  end,
  disable_filetype = function(filetype)
    LanguageService:disable_filetype(filetype)
  end,
  configure_lsp = function(config)
    LanguageService:configure_lsp(config)
  end,
  configure_linter = function(config)
    LanguageService:configure_linter(config)
  end,
  shutdown = function()
    LanguageService:shutdown_all()
  end,
  definition = definition,
  diagnostics = diagnostics,
  type_definition = type_definition,
  hover = hover,
  next_diagnostic_location = next_diagnostic_location,
  prev_diagnostic_location = prev_diagnostic_location,
}
