local fs = require 'mode.fs'
local util = require 'mode.util'
local logging = require 'mode.logging'
local path = require 'mode.path'
local lsp = require 'mode.lsp'
local Linter = require 'mode.linter'
local diagnostics = require 'mode.diagnostics'
local vim = require 'mode.vim'

local log = logging.get_logger('language_service')

local function toarray(value)
  if util.table.is_array(value) then
    return value
  else
    return {value}
  end
end

local LanguageService = {
  _by_root = {},
  _by_buffer = {},
  _config_by_filetype = {},
  _enabled_by_filetype = {},
  _rtp_searched_by_filetype = {},
}

function LanguageService:enable_filetype(filetype)
  self._enabled_by_filetype[filetype] = true
end

function LanguageService:disable_filetype(filetype)
  self._enabled_by_filetype[filetype] = false
end

function LanguageService:configure_lsp(config)
  assert(config.id, 'missing id')
  assert(config.id, 'missing filetype')
  for _, filetype in ipairs(toarray(config.filetype)) do
    self._config_by_filetype[filetype] = {
      type = 'lsp',
      config = config,
      enabled = true,
    }
  end
end

function LanguageService:configure_linter(config)
  assert(config.id, 'missing id')
  assert(config.id, 'missing filetype')
  for _, filetype in ipairs(toarray(config.filetype)) do
    self._config_by_filetype[filetype] = {
      type = 'linter',
      config = config,
      enabled = true,
    }
  end
end

function LanguageService:get_lsp_for_config(config)
  local filename = path.split(vim.call.expand("%:p"))
  local root = config.root(filename)
  if not root then
    return
  end

  local services = self._by_root[root.string] or {}
  local service = services[config.id]
  if service then
    return service
  end

  log:info('starting lsp %s@%s', config.id, root.string)
  local cmd, args = config.command(root)
  service = lsp.LSPClient:start {
    id = config.id,
    languageId = config.languageId,
    root = root,
    cmd = cmd,
    args = args
  }
  self._by_root[root.string] = self._by_root[root.string] or {}
  self._by_root[root.string][config.id] = service
  return service
end

function LanguageService:get_linter_for_config(config)
  local filename = path.split(vim.call.expand("%:p"))
  local root = config.root(filename)
  if not root then
    return
  end

  local services = self._by_root[root.string] or {}
  local service = services[config.id]
  if service then
    return service
  end

  log:info('starting linter %s@%s', config.id, root.string)
  local cmd, args = config.command(root)
  service = Linter:start {
    id = config.id,
    cmd = cmd,
    args = args,
    cwd = root,
    produce = config.produce,
  }
  service.diagnostics:subscribe(function(reports)
    for _, report in ipairs(reports) do
      diagnostics:set(report.filename, report.items)
    end
    vim.wait()
    diagnostics:update()
  end)

  self._by_root[root.string] = self._by_root[root.string] or {}
  self._by_root[root.string][config.id] = service
  return service
end

function LanguageService:get(o)
  o = o or {}
  local type = o.type
  local buffer = o.buffer or vim.Buffer:current()

  local service

  service = self._by_buffer[buffer.id]
  if service then
    if type and type ~= service.type then
      return nil, false
    end
    return service, true
  end

  local filetype = buffer.options.filetype

  local enabled = self._enabled_by_filetype[filetype]
  if enabled ~= nil and not enabled then
    return nil, false
  end

  -- Load configuration from &runtimepath/mode/filetype/&filetype.lua
  -- TODO(andreypopp): Need to move it closer to autocmd
  if not self._rtp_searched_by_filetype[filetype] then
    local paths = vim._vim.api.nvim_list_runtime_paths()
    for _, p in ipairs(paths) do
      local name = filetype .. '.lua'
      local mode_config = path.split(p) / 'mode' / 'filetype' / name
      if fs.exists(mode_config) then
        log:info('loading filetype config %s', mode_config.string)
        dofile(mode_config.string)
      end
    end
    self._rtp_searched_by_filetype[filetype] = true
  end

  local config = self._config_by_filetype[filetype]
  if not config then
    return nil, false
  end

  if type and type ~= config.type then
    return nil, false
  end

  if config.type == 'lsp' then
    service = self:get_lsp_for_config(config.config)
  elseif config.type == 'linter' then
    service = self:get_linter_for_config(config.config)
  else
    assert(false, "Unknown language service type: " .. config.type)
  end

  self._by_buffer[buffer.id] = service
  return service, false
end

function LanguageService:shutdown_all()
  for _, services in pairs(self._by_root) do
    for _, service in pairs(services) do
      service:shutdown()
    end
  end
end

vim.autocommand.register {
  event = vim.autocommand.VimLeavePre,
  pattern = '*',
  action = function()
    log:info('shutdown_all')
    LanguageService:shutdown_all()
  end
}

vim.autocommand.register {
  event = vim.autocommand.BufUnload,
  pattern = '*',
  action = function(ev)
    local service = LanguageService:get { buffer = ev.buffer }
    if service then
      log:info('did_close %s', ev.buffer:name())
      service:did_close(ev.buffer)
    end
    LanguageService._by_buffer[ev.buffer.id] = nil
  end
}

vim.autocommand.register {
  event = vim.autocommand.FileType,
  pattern = '*',
  action = function(ev)
    local service, seen = LanguageService:get { buffer = ev.buffer }
    if service and not seen then
      log:info('did_open %s', ev.buffer:name())
      service:did_open(ev.buffer)
    end
  end
}

vim.autocommand.register {
  event = vim.autocommand.InsertEnter,
  pattern = '*',
  action = function(ev)
    local service = LanguageService:get { buffer = ev.buffer }
    if service then
      service:did_insert_enter(ev.buffer)
    end
  end
}

vim.autocommand.register {
  event = vim.autocommand.BufEnter,
  pattern = '*',
  action = function(ev)
    local service = LanguageService:get { buffer = ev.buffer }
    if service then
      service:did_buffer_enter(ev.buffer)
    end
  end
}

vim.autocommand.register {
  event = vim.autocommand.InsertLeave,
  pattern = '*',
  action = function(ev)
    local service = LanguageService:get { buffer = ev.buffer }
    if service then
      service:did_insert_leave(ev.buffer)
    end
  end
}

return LanguageService
