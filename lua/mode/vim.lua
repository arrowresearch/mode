-- luacheck: globals vim
--
-- High level wrapper around neovim Lua API.
--

local util = require 'mode.util'

-- Wait for VIM API to be available.
--
-- This assumes that if no coroutine is running then it's safe to call into vim.

local function wait()
  if not vim.in_fast_event() then
    return
  end
  local running = coroutine.running()
  assert(running, 'Should be called from a coroutine')
  vim.schedule(function()
    assert(coroutine.resume(running))
  end)
  coroutine.yield()
end

-- Proxy for convenient calls to vim functions.
--
-- Example (getting the current buffer filename):
--
--   local vim = require 'mode.vim'
--   local filename = vim.call.expand("%:p")

local call_meta = {
  __index = function(_, k)
    return function(...)
      local args = util.table_pack(...)
      return vim.api.nvim_call_function(k, args)
    end
  end
}

local call = {}
setmetatable(call, call_meta)

--
-- Execute vim commands.
--

local function execute(cmd, ...)
  vim.api.nvim_command(string.format(cmd, ...))
end

--
-- Autocommands
--

local _autocommand_callback = {}
local _autocommand_id = 0

local _autocommand_events = {
  'BufNewFile',
  'BufReadPre',
  'BufRead',
  'BufReadPost',
  'BufReadCmd',
  'FileReadPre',
  'FileReadPost',
  'FileReadCmd',
  'FilterReadPre',
  'FilterReadPost',
  'StdinReadPre',
  'StdinReadPost',
  'BufWrite',
  'BufWritePre',
  'BufWritePost',
  'BufWriteCmd',
  'FileWritePre',
  'FileWritePost',
  'FileWriteCmd',
  'FileAppendPre',
  'FileAppendPost',
  'FileAppendCmd',
  'FilterWritePre',
  'FilterWritePost',
  'BufAdd',
  'BufCreate',
  'BufDelete',
  'BufWipeout',
  'BufFilePre',
  'BufFilePost',
  'BufEnter',
  'BufEnter',
  'BufLeave',
  'BufWinEnter',
  'BufWinLeave',
  'BufUnload',
  'BufHidden',
  'BufNew',
  'SwapExists',
  'TermOpen',
  'TermClose',
  'ChanOpen',
  'ChanInfo',
  'FileType',
  'Syntax',
  'OptionSet',
  'VimEnter',
  'GUIEnter',
  'GUIFailed',
  'TermResponse',
  'QuitPre',
  'ExitPre',
  'VimLeavePre',
  'VimLeave',
  'VimResume',
  'VimSuspend',
  'DiffUpdated',
  'DirChanged',
  'FileChangedShell',
  'FileChangedShell',
  'FileChangedRO',
  'ShellCmdPost',
  'ShellFilterPost',
  'CmdUndefined',
  'FuncUndefined',
  'SpellFileMissing',
  'SourcePre',
  'SourcePost',
  'SourceCmd',
  'VimResized',
  'FocusGained',
  'FocusLost',
  'CursorHold',
  'CursorHoldI',
  'CursorMoved',
  'CursorMovedI',
  'WinNew',
  'WinEnter',
  'WinLeave',
  'TabEnter',
  'TabLeave',
  'TabNew',
  'TabNewEntered',
  'TabClosed',
  'CmdlineChanged',
  'CmdlineEnter',
  'CmdlineLeave',
  'CmdwinEnter',
  'CmdwinLeave',
  'InsertEnter',
  'InsertChange',
  'InsertLeave',
  'InsertCharPre',
  'TextYankPost',
  'TextChanged',
  'TextChangedI',
  'TextChangedP',
  'ColorSchemePre',
  'ColorScheme',
  'RemoteReply',
  'QuickFixCmdPre',
  'QuickFixCmdPost',
  'SessionLoadPost',
  'MenuPopup',
  'CompleteChanged',
  'CompleteDone',
  'User',
  'Signal',
}

local autocommand = {}

for _, name in ipairs(_autocommand_events) do
  autocommand[name] = name
end

local function autocommand_destroy(id)
  local group = "_lua_group_" .. tostring(id)
  execute([[autocmd! %s]], group, id)
  _autocommand_callback[id] = nil
end

function autocommand.register(o)

  local event = o.event
  assert(event ~= nil, 'autocommand.register: event is not provided')
  if type(event) == "table" then
    event = table.concat(event, ",")
  end

  local eventstring = event
  if o.pattern ~= nil then
    eventstring = eventstring .. " " .. o.pattern
  end

  _autocommand_id = _autocommand_id + 1
  local id = _autocommand_id
  local group = "_lua_group_" .. tostring(id)
  execute([[augroup %s]], group)
  execute(
    [[autocmd %s %s :lua require('mode.vim').autocommand._trigger(%i)]],
    group, eventstring, id
  )
  _autocommand_callback[id] = o.action
  return function()
    autocommand_destroy(id)
  end
end

function autocommand._trigger(id)
  local cb = _autocommand_callback[id]
  assert(cb ~= nil, 'Unknown autocommand id')
  cb()
end

local function show(o)
  wait()
  print(vim.inspect(o))
end

return {
  _vim = vim,
  call = call,
  execute = execute,
  wait = wait,
  show = show,
  autocommand = autocommand,
}
