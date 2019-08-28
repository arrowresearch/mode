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
  _config_by_filetype = {},
}

function LanguageService:configure_lsp(config)
  for _, filetype in ipairs(toarray(config.filetype)) do
    self._config_by_filetype[filetype] = {type = 'lsp', config = config}
  end
end

function LanguageService:configure_linter(config)
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

  local id = root.string
  local service = self._by_root[id]
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
  self._by_root[id] = service
  return service
end

function LanguageService:linter_for_config(config)
  local filename = path.split(vim.call.expand("%:p"))
  local root = config.root(filename)
  if not root then
    return
  end

  local id = root.string
  local service = self._by_root[id]
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
  self._by_root[id] = service
  return service
end

function LanguageService:get(o)
  o = o or {type = nil}
  local filetype = vim._vim.api.nvim_buf_get_option(0, 'filetype')
  local config = self._config_by_filetype[filetype]
  if not config then
    return
  end

  if o.type and o.type ~= config.type then
    return nil
  end

  if config.type == 'lsp' then
    return self:lsp_for_config(config.config)
  elseif config.type == 'linter' then
    return self:linter_for_config(config.config)
  else
    assert(false, "Unknown language service type: " .. config.type)
  end
end

function LanguageService:shutdown(id)
  local service = self._by_root[id]
  self._by_root[id] = nil
  assert(service, 'LanguageService.shutdown: unable to find server')
  service:shutdown()
end

function LanguageService:shutdown_all()
  for id, _ in pairs(self._by_root) do
    self:shutdown(id)
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
  event = vim.autocommand.FileType,
  pattern = '*',
  action = function()
    async.task(function()
      local buffer = vim.call.bufnr('%')
      local service = LanguageService:get()
      if service then
        service:did_open(buffer)
      end
    end)
  end
}

vim.autocommand.register {
  event = vim.autocommand.InsertEnter,
  pattern = '*',
  action = function()
    local service = LanguageService:get()
    if service then
      async.task(function()
        service:did_insert_enter(vim.call.bufnr('%'))
      end)
    end
  end
}

vim.autocommand.register {
  event = vim.autocommand.InsertLeave,
  pattern = '*',
  action = function()
    local service = LanguageService:get()
    if service then
      async.task(function()
        service:did_insert_leave(vim.call.bufnr('%'))
      end)
    end
  end
}

return LanguageService
