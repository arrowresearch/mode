-- luacheck: globals vim
--
-- High level wrapper around neovim Lua API.
--

local util = require 'mode.util'
local path = require 'mode.path'
local async = require 'mode.async'

--- Wait for vim API to be available.
--
-- Note that this can return immediately if vim API is safe to use at the
-- moment. Pass |force| in case you want to force it to yield which can be
-- useful, for example, to wait for input to be processed by neovim.
local function wait(force)
  if not force and not vim.in_fast_event() then
    return
  end
  local running = async.running()
  assert(running, 'vim.wait() should be called from a coroutine')
  vim.schedule(function() async.resume(running) end)
  async.yield()
end

local function wait_cb(cb)
  vim.schedule(cb)
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
  cmd = cmd:format(...)
  vim.api.nvim_command(cmd)
end

--
-- Wrap window API
--

local Window = util.Object:extend()

function Window.__eq(a, b)
  return a.id == b.id
end

function Window:init(id)
  self.id = id
end

function Window:current()
  local id = call.win_getid()
  return self:new(id)
end

function Window:focus()
  call.win_gotoid(self.id)
end

function Window:number()
  local number = call.win_id2win(self.id)
  if number == 0 then
    return nil
  else
    return number
  end
end

function Window:close(o)
  o = o or {force = false}
  vim.api.nvim_win_close(self.id, o.force)
end

--
-- Wrap buffer API
--

local Buffer = util.Object:extend()

local function make_buffer_options_proxy(id)
  local t = {}
  setmetatable(t, {
    __index = function(_, k)
      return vim.api.nvim_buf_get_option(id, k)
    end,
    __newindex = function(_, k, v)
      return vim.api.nvim_buf_set_option(id, k, v)
    end
  })
  return t
end

local function make_buffer_vars_proxy(id)
  local t = {}
  setmetatable(t, {
    __index = function(_, k)
      return vim.api.nvim_buf_get_var(id, k)
    end,
    __newindex = function(_, k, v)
      return vim.api.nvim_buf_set_var(id, k, v)
    end
  })
  return t
end

function Buffer.__eq(a, b)
  return a.id == b.id
end

function Buffer:init(id)
  self.id = id
  self.options = make_buffer_options_proxy(id)
  self.vars = make_buffer_vars_proxy(id)
end

function Buffer:create(o)
  o = o or {listed = true, scratch = false, modifiable = false}
  local id = vim.api.nvim_create_buf(o.listed, o.scratch)
  return self:new(id)
end

function Buffer:get_or_nil(id)
  if type(id) == "string" then
    id = call.bufnr(id)
  end
  if not vim.api.nvim_buf_is_valid(id) then
    return nil
  end
  return self:new(id)
end

function Buffer:get(id)
  local buf = self:get_or_nil(id)
  assert(buf, 'Invalid buffer id')
  return buf
end

function Buffer:current()
  return self:new(vim.api.nvim_get_current_buf())
end

function Buffer:filename()
  return path.split(vim.api.nvim_buf_get_name(self.id))
end

function Buffer:name()
  return vim.api.nvim_buf_get_name(self.id)
end

function Buffer:set_name(name)
  return vim.api.nvim_buf_set_name(self.id, name)
end

function Buffer:changedtick()
  return vim.api.nvim_buf_get_changedtick(self.id)
end

function Buffer:window()
  local win_id = call.bufwinid(self.id)
  if win_id == -1 then
    return nil
  else
    return Window:new(win_id)
  end
end

function Buffer:append_lines(lines)
  return vim.api.nvim_buf_set_lines(self.id, 0, 0, false, lines)
end

function Buffer:set_lines(lines, start, stop)
  start = start == nil and 0 or start
  stop = stop == nil and -1 or stop
  return vim.api.nvim_buf_set_lines(self.id, start, stop, false, lines)
end

function Buffer:contents_lines(start, stop, strict_indexing)
  start = start == nil and 0 or start
  stop = stop == nil and -1 or stop
  strict_indexing = strict_indexing == nil and true or false
  return vim.api.nvim_buf_get_lines(self.id, start, stop, strict_indexing)
end

function Buffer:contents()
  local lines = self:contents_lines()
  return table.concat(lines, '\n')
end

function Buffer:exists()
  -- TODO(andreypopp): is it an adequate way to check if the buffer is valid?
  return call.bufname(self.id) ~= ''
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

  if o.buffer ~= nil then
    eventstring = eventstring .. string.format(" <buffer=%i>", o.buffer.id)
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
  cb {
    filename = call.expand('<afile>'),
    buffer = Buffer:new(tonumber(call.expand('<abuf>'))),
  }
end

local function show(o)
  wait()
  print(vim.inspect(o))
end

local callback = {
  _id = 0,
  _registry = {},
}

function callback.wrap(f)
  callback._id = callback._id + 1
  local id = 'cb__' .. tostring(callback._id)
  callback._registry[id] = function()
    callback._registry[id] = nil
    f()
  end
  return id
end

function callback.execute(id)
  local cb = callback._registry[id]
  assert(cb, 'No callback found')
  cb()
end

execute [[
function Mode_lua_callback(id, ...)
  exec "lua require('mode.vim').callback.execute('".a:id."')"
endfunction
]]

local function termopen(o)
  assert(o.cmd)
  assert(o.on_exit)
  local cb = callback.wrap(function()
    vim.schedule(function()
      o.on_exit()
    end)
  end)
  execute([[
    call termopen('%s', {'on_exit': function('Mode_lua_callback', ['%s'])})
  ]], o.cmd, cb)
end

local function echomsg(m, ...)
  m = m:gsub("%%", "%%%%")
  m = m:format(...)
  execute([[ echomsg '%s' ]], m)
end

local function echo(m, ...)
  m = m:gsub("%%", "%%%%")
  m = m:format(...)
  execute([[ echo '%s' ]], m)
end

return {
  _vim = vim,
  Buffer = Buffer,
  Window = Window,
  call = call,
  execute = execute,
  wait = wait,
  wait_cb = wait_cb,
  show = show,
  autocommand = autocommand,
  termopen = termopen,
  callback = callback,
  echomsg = echomsg,
  echo = echo,
}
