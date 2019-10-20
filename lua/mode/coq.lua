local util = require 'mode.util'
local logging = require 'mode.logging'
local uv = require 'mode.uv'
local vim = require 'mode.vim'
local async = require 'mode.async'
local sexp = require 'mode.sexp'
local highlights = require 'mode.highlights'
local BufferWatcher = require 'mode.buffer_watcher'

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

local Coq = util.Object:extend()

function Coq:init(_o)
  self.cwd = nil
  self.log = logging.get_logger("coq")
  self.tip = nil
  self.highlights = highlights.Highlights:new {name = 'coq'}
  self.buf = vim.Buffer:current()
  self.buf_watcher = BufferWatcher:new {
    buffer = self.buf,
    is_utf8 = false,
  }
  self.buf_watcher.updates:subscribe(function(...) self:_on_buf_update(...) end)
  self.commands = {}
  self.commands_idx = 0

  self.proc = self:_start_sertop()
  self.stop = read_lines(self.proc.stdout, function(line)
    self.log:info("<<< " .. line)
    local value = sexp.parse(line)
    local tag = value[1]
    if tag == "Feedback" then
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

function Coq:send(cmd)
  local future = async.Future:new()
  self.commands[self.commands_idx] = {
    future = future,
    ok = {},
    error = {},
  }
  self.commands_idx = self.commands_idx + 1
  local line = sexp.print(cmd)
  self.log:info(">>> " .. line)
  self.proc.stdin:write(line)
  return future
end

function Coq:set_tip(tip)
  self.highlights:clear(self.buf)
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
  self.tip = tip
end

function Coq:prev()
  if self.tip == nil then
    return
  end
  local tip = self.tip
  self:send({"Cancel", {tip.sentence.id}}):wait()
  self:set_tip(tip.parent)
end

function Coq:add_till_cursor()
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
  self:set_tip(tip)

  if #to_cancel > 0 then
    -- Ignoring errors on cancel, it seems like it does more than needed.
    self:send({"Cancel", to_cancel}):wait()
  end

  local opts = {}
  if tip ~= nil then
    opts = sexp.of_table { ontop = tip.sentence.id }
    body = body:sub(tip.sentence.ep + 1)
  end

  local add = self:send({"Add", opts, body}):wait()
  local sentences = add.ok

  local invalid = {}
  local valid = {}
  for _, sentence in ipairs(sentences) do
    local exec = self:send({"Exec", sentence.id}):wait()
    if #exec.error ~= 0 then
      table.insert(invalid, sentence.id)
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
      sentence = {
        id = sentence.id,
        -- fixup bp/ep offset
        bp = tip and tip.sentence.ep + sentence.bp or sentence.bp,
        ep = tip and tip.sentence.ep + sentence.ep or sentence.ep,
      }
    }
  end
  self:set_tip(next_tip)
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
      self:set_tip(tip)
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

return {
  init = function() async.task(function()
    coq = Coq:new()
  end) end,
  prev = function() async.task(function()
    coq:prev()
  end) end,
  add_till_cursor = function() async.task(function()
    coq:add_till_cursor()
  end) end,
}
