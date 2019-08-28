local async = require 'mode.async'
local util = require 'mode.util'
local path = require 'mode.path'
local lsp = require 'mode.lsp'
local Linter = require 'mode.linter'
local diagnostics = require 'mode.diagnostics'
local vim = require 'mode.vim'

local function toarray(value)
  if util.table_is_array(value) then
    return value
  else
    return {value}
  end
end

local LanguageService = {
  _by_root = {},
  _by_buffer = {},
  _config_by_filetype = {},
}

function LanguageService:configure_lsp(config)
  assert(config.id, 'missing id')
  assert(config.id, 'missing filetype')
  for _, filetype in ipairs(toarray(config.filetype)) do
    self._config_by_filetype[filetype] = {type = 'lsp', config = config}
  end
end

function LanguageService:configure_linter(config)
  assert(config.id, 'missing id')
  assert(config.id, 'missing filetype')
  for _, filetype in ipairs(toarray(config.filetype)) do
    self._config_by_filetype[filetype] = {type = 'linter', config = config}
  end
end

function LanguageService:lsp_for_config(config)
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

  local cmd, args = config.command(root)
  service = lsp.LSPClient:start {
    languageId = config.languageId,
    root = root,
    cmd = cmd,
    args = args
  }
  self._by_root[root.string] = self._by_root[root.string] or {}
  self._by_root[root.string][config.id] = service
  return service
end

function LanguageService:linter_for_config(config)
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

  local cmd, args = config.command(root)
  service = Linter:start {
    cmd = cmd,
    args = args,
    cwd = root,
    produce = config.produce,
  }
  service.diagnostics:subscribe(function(reports)
    for _, report in ipairs(reports) do
      diagnostics:set(filename, report.items)
    end
    diagnostics:update()
  end)

  self._by_root[root.string] = self._by_root[root.string] or {}
  self._by_root[root.string][config.id] = service
  return service
end

function LanguageService:get(o)
  o = o or {}
  local type = o.type
  local buffer = o.buffer or vim.call.expand('%')

  local service

  service = self._by_buffer[buffer]
  if service then
    return service
  end

  local filetype = vim._vim.api.nvim_buf_get_option(buffer, 'filetype')
  local config = self._config_by_filetype[filetype]
  if not config then
    return
  end

  if type and type ~= config.type then
    return nil
  end

  if config.type == 'lsp' then
    service = self:lsp_for_config(config.config)
  elseif config.type == 'linter' then
    service = self:linter_for_config(config.config)
  else
    assert(false, "Unknown language service type: " .. config.type)
  end

  self._by_buffer[buffer] = service
  return service
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
    async.task(function()
      LanguageService:shutdown_all()
    end)
  end
}

vim.autocommand.register {
  event = vim.autocommand.BufUnload,
  pattern = '*',
  action = function(ev)
    async.task(function()
      local service = LanguageService:get { buffer = ev.buffer }
      if service then
        service:did_close(ev.buffer)
      end
      LanguageService._by_buffer[ev.buffer] = nil
    end)
  end
}

vim.autocommand.register {
  event = vim.autocommand.FileType,
  pattern = '*',
  action = function(ev)
    async.task(function()
      local service = LanguageService:get { buffer = ev.buffer }
      if service then
        service:did_open(ev.buffer)
      end
    end)
  end
}

vim.autocommand.register {
  event = vim.autocommand.InsertEnter,
  pattern = '*',
  action = function(ev)
    async.task(function()
      local service = LanguageService:get { buffer = ev.buffer }
      if service then
        async.task(function()
          service:did_insert_enter(ev.buffer)
        end)
      end
    end)
  end
}

vim.autocommand.register {
  event = vim.autocommand.InsertLeave,
  pattern = '*',
  action = function(ev)
    async.task(function()
      local service = LanguageService:get { buffer = ev.buffer }
      if service then
        async.task(function()
          service:did_insert_leave(ev.buffer)
        end)
      end
    end)
  end
}

return LanguageService
