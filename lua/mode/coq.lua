local util = require 'mode.util'
local logging = require 'mode.logging'
local uv = require 'mode.uv'
local vim = require 'mode.vim'
local async = require 'mode.async'
local sexp = require 'mode.sexp'
local highlights = require 'mode.highlights'
local BufferWatcher = require 'mode.buffer_watcher'
local Diagnostics = require 'mode.diagnostics'

local function read_lines(stream, f)
  local prev = ""
  local read_stop = stream:read_start(function(chunk)
    while chunk:len() > 0 do
      local s, e = chunk:find("[\r\n]+")
      if s == nil then
        prev = prev .. chunk
        break
      else
        local line = prev .. chunk:sub(1, s - 1)
        prev = ""
        vim.wait_cb(function() f(line) end)
        chunk = chunk:sub(e + 1)
      end
    end
  end)
  return read_stop
end

local function current_position()
  local pos = vim.call.getpos('.')
  local lnum = pos[2]
  local coln = pos[3]
  local bp = vim.call.line2byte(lnum) + coln - 1
  return {bp = bp, lnum = lnum, coln = coln}
end

local function byte2position(bp)
  local lnum = vim.call.byte2line(bp + 1)
  local start_bp = vim.call.line2byte(lnum)
  local coln = bp - start_bp + 1
  return {bp = bp, lnum = lnum, coln = coln}
end

local function is_bullet(c)
  return c == '*'
      or c == '-'
      or c == '+'
end

local function is_punc(c)
  return c == '.'
      or c == '{'
      or c == '}'
end

local function find_next_sentence(buf, pos)
  local start_of_line
  local text
  if pos == nil then
    text = buf:contents_lines()
    text = util.table_concat(text, '\n')
    start_of_line = true
  else
    text = buf:contents_lines(pos.lnum - 1)
    text = util.table_concat(text, '\n')
    text = text:sub(pos.coln + 1)
    start_of_line = false
  end

  local sentence = ''
  while #text > 0 do
    -- TODO(andreypopp): handle nested comments
    if text:sub(0, 2) == '(*' then
      start_of_line = false
      local _, comment_end = text:find("%*%)") -- find '*)'
      if comment_end == nil then -- unclosed comment
        return nil
      end
      sentence = sentence .. text:sub(0, comment_end)
      text = text:sub(comment_end + 1)
    else
      local c = text:sub(0, 1)
      if c == '"' then
      -- TODO(andreypopp): handle escapes
        local _, s_end = text:sub(2):find('"') -- find end of string
        sentence = sentence .. text:sub(0, s_end + 1)
        text = text:sub(s_end + 2)
      elseif c == '\n' then
        local _, ws_end = text:find("[^%s]") -- find non whitespace
        sentence = sentence .. text:sub(0, ws_end - 1)
        text = text:sub(ws_end)
        start_of_line = true
      elseif is_bullet(c) and start_of_line then
        sentence = sentence .. c
        return sentence
      elseif is_punc(c) then
        sentence = sentence .. c
        return sentence
      else
        start_of_line = false
        sentence = sentence .. c
        text = text:sub(2)
      end
    end
  end
  return nil
end

local Coq = util.Object:extend()

function Coq:init(_o)
  self.cwd = nil
  self.log = logging.get_logger("coq")
  self.highlights = highlights.Highlights:new {name = 'coq'}
  self.buf = vim.Buffer:current()
  self.buf_goals = vim.Buffer:create {
    listed = false,
    scratch = true,
    modifiable = false
  }
  self.buf_goals:set_name('** goals **')

  self.buf_messages = vim.Buffer:create {
    listed = false,
    scratch = true,
    modifiable = false
  }
  self.buf_messages:set_name('** messages **')

  self.buf_watcher = BufferWatcher:new {
    buffer = self.buf,
    is_utf8 = false,
  }
  self.buf_watcher.updates:subscribe(function(...) self:_on_buf_update(...) end)
  self.commands = {}
  self.commands_idx = 0

  self.tip = nil
  self.error = nil
  self.messages = {}

  self:_layout()
  self.proc = self:_start_sertop()
  self.stop = read_lines(self.proc.stdout, function(line)
    self.log:info("<<< %s", line)
    local value = sexp.parse(line)
    local tag = value[1]
    if tag == "Feedback" then
      local feedback = sexp.to_table(value[2])
      local contents = feedback.contents
      if contents ~= nil
        and contents[1] == 'Message'
        and contents[2] == 'Notice' then
        local obj = {'CoqPp', contents[4]}
        table.insert(self.messages, obj)
      end
    elseif tag == "Answer" then
      local idx = value[2]
      local answer = value[3]
      local res = self.commands[idx]
      if answer == "Ack" then
        -- ok...
      elseif answer == "Completed" then
        self.commands[idx] = nil
        res.future:put(res)
      elseif answer[1] == "CoqExn" then
        table.insert(res.error, {"Error"})
      elseif answer[1] == "ObjList" then
        for _, obj in ipairs(answer[2]) do
          table.insert(res.ok, obj)
        end
      elseif answer[1] == "Added" then
        local id = answer[2]
        local info = sexp.to_table(answer[3])
        table.insert(res.ok, {
          id = id,
          bp = info.bp,
          ep = info.ep
        })
      end
    end
  end)

end

function Coq:_layout()
  local winnr = vim.call.winnr()
  vim.execute("vertical belowright sbuffer %i", self.buf_goals.id)
  vim.execute("belowright sbuffer %i", self.buf_messages.id)
  vim.execute("%iwincmd w", winnr)
end

function Coq:send(cmd)
  local future = async.Future:new()
  self.commands[self.commands_idx] = {
    future = future,
    ok = {},
    error = {},
  }
  self.commands_idx = self.commands_idx + 1
  local line = sexp.print(cmd)
  self.log:info(">>> %s", line)
  self.proc.stdin:write(line)
  return future
end

function Coq:set_tip(tip, error)
  self.highlights:clear(self.buf)

  -- Mark region as checked based on the new tip.
  do
    if tip ~= nil then
      local e = byte2position(tip.sentence.ep)
      self.highlights:add {
        range = {
          start = {
            line = 0,
            character = 0,
          },
          ['end'] = {
            line = e.lnum - 1,
            character = e.coln,
          },
        },
        hlgroup = 'CoqModeChecked',
        buffer = self.buf,
      }
    end
  end

  -- Mark region as error based on a the new error.
  do
    if error ~= nil then
      local s = byte2position(error.sentence.bp)
      local e = byte2position(error.sentence.ep)
      Diagnostics:set(self.buf:filename(), {{
        message = error.message,
        range = {
          start = {
            line = s.lnum - 1,
            character = s.coln,
          },
          ['end'] = {
            line = e.lnum - 1,
            character = e.coln,
          },
        },
      }})
      Diagnostics:update()
    else
      Diagnostics:set(self.buf:filename(), {})
      Diagnostics:update()
    end
  end

  -- Update messages if any were found.
  do
    if #self.messages > 0 then
      local messages = self.messages
      self.messages = {}
      self.buf_messages:set_lines(self:print(messages))
    else
      self.buf_messages:set_lines({})
    end
  end

  -- Update goals.
  do
    local query_opt = sexp.of_table {limit = nil, preds = {}}
    local goals = self:send({"Query", query_opt, 'Goals'}):wait()
    local goals_lines = self:print(goals.ok)
    self.buf_goals:set_lines(goals_lines)
  end

  self.tip = tip
  self.error = error
end

-- Print a coq_obj list into a string list.
function Coq:print(objs)
  local lines = {}
  for _, obj in ipairs(objs) do
    local print_opt = sexp.of_table {pp_format = 'PpStr'}
    local pp = self:send({"Print", print_opt, obj}):wait()
    for _, v in ipairs(pp.ok) do
      assert(v[1] == 'CoqString')
      local vlines = v[2]
      for line in vlines:gmatch("[^\r\n]+") do
          table.insert(lines, line)
      end
    end
  end
  return lines
end

function Coq:prev()
  if self.tip == nil then
    return
  end
  local tip = self.tip
  self:send({"Cancel", {tip.sentence.id}}):wait()
  self:set_tip(tip.parent, nil)
end

function Coq:next()
  local pos = nil
  if self.tip ~= nil then
    pos = byte2position(self.tip.sentence.ep)
  end
  local sentence = find_next_sentence(self.buf, pos)
  return self:_add(self.tip, sentence)
end

function Coq:at_position()
  local pos = current_position()
  local lines = self.buf:contents_lines(0, pos.lnum)
  local len = #lines
  local body = nil
  for idx, line in ipairs(lines) do
    if body == nil then
      body = ''
    else
      body = body .. '\n'
    end
    if idx == len then
      body = body .. line:sub(1, pos.coln)
    else
      body = body .. line
    end
  end

  local tip = self.tip
  local to_cancel = {}
  while tip ~= nil do
    local s = tip.sentence
    if s.ep < pos.bp then
      break
    end
    table.insert(to_cancel, tip.sentence.id)
    tip = tip.parent
  end
  self:set_tip(tip, nil)

  if #to_cancel > 0 then
    -- Ignoring errors on cancel, it seems like it does more than needed.
    self:send({"Cancel", to_cancel}):wait()
  end

  if tip ~= nil then
    body = body:sub(tip.sentence.ep + 1)
  end

  return self:_add(tip, body)
end

function Coq:_add(tip, body)
  local opts = {}
  if tip ~= nil then
    opts = sexp.of_table { ontop = tip.sentence.id }
  end

  local add = self:send({"Add", opts, body}):wait()
  local sentences = add.ok

  local invalid = {}
  local valid = {}
  local error = nil
  for _, sentence in ipairs(sentences) do

    -- Fixup bp and ep as they are reported against ontop
    sentence = {
      id = sentence.id,
      bp = tip and tip.sentence.ep + sentence.bp or sentence.bp,
      ep = tip and tip.sentence.ep + sentence.ep or sentence.ep,
    }

    -- Need to Exec each sentence to check it's validity
    local exec = self:send({"Exec", sentence.id}):wait()

    -- We partition sentences into valid and invalid.
    if #exec.error ~= 0 then
      table.insert(invalid, sentence.id)
      -- Report first error.
      if error == nil then
        error = {
          message = "Error here!",
          sentence = sentence
        }
      end
      -- Collect all additions before the first error
    elseif #invalid == 0 then
      table.insert(valid, sentence)
    end
  end

  -- Need to cancel all invalid additions so we can have a valid tip.
  -- Check if we need this with 8.10
  if #invalid > 0 then
    self:send({"Cancel", invalid}):wait()
  end

  local next_tip = tip
  for _, sentence in ipairs(valid) do
    next_tip = {
      parent = next_tip,
      sentence = sentence,
    }
  end
  self:set_tip(next_tip, error)
end

function Coq:shutdown()
  self.stop()
  self.buf_watcher:shutdown()
  return self.proc:shutdown()
end

function Coq:_on_buf_update(update)
  async.task(function()
    local lnum = update.start + 1
    local bp = vim.call.line2byte(lnum) - 1
    local tip = self.tip
    local to_cancel = {}
    while tip ~= nil do
      if tip.sentence.ep < bp then
        break
      end
      table.insert(to_cancel, tip.sentence.id)
      tip = tip.parent
    end
    if #to_cancel > 0 then
      self:send({"Cancel", to_cancel}):wait()
      self:set_tip(tip, nil)
    end
  end)
end

function Coq:_start_sertop()
  local _, proc = assert(pcall(uv.spawn, {
    cmd = "sertop",
    args = {"--async-full"},
    cwd = self.cwd,
  }))
  return proc
end

local coq = nil

vim.autocommand.register {
  event = vim.autocommand.VimLeavePre,
  pattern = '*',
  action = function()
    if coq ~= nil then
      async.task(function()
        coq:shutdown():wait()
      end)
    end
  end
}

local function init()
  async.task(function()
    coq = Coq:new()
  end)
end

local function prev()
  async.task(function()
    if coq == nil then coq = Coq:new() end
    coq:prev()
  end)
end

local function next()
  async.task(function()
    if coq == nil then coq = Coq:new() end
    coq:next()
  end)
end

local function at_position()
  async.task(function()
    if coq == nil then coq = Coq:new() end
    coq:at_position()
  end)
end

return {
  init = init,
  prev = prev,
  next = next,
  at_position = at_position,
}
