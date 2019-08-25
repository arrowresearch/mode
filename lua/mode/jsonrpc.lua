-- luacheck: globals vim
-- JSON RPC

local util = require 'mode.util'
local async = require 'mode.async'

-- JSONRPCClient

local JSONRPCClient = util.Object:extend()

function JSONRPCClient:init(o)
  self.stream_input = o.stream_input
  self.stream_output = o.stream_output
  self.notifications = async.Channel:new()
  self.callbacks = {}
  self.request_id = 0
  self.read_stop = nil
  self:start()
end

function JSONRPCClient:start()
  local buf = ""

  local function on_stdout(chunk)
    if not chunk then
      return
    end
    buf = buf .. chunk
    local eol = string.find(buf, '\r\n')
    if not eol then
      return
    end
    local line = string.sub(buf, 1, eol - 1)
    local space = string.find(line, " ")
    local length = tonumber(string.sub(line,space+1))
    -- TODO: can has Content-Type??
    if string.len(buf) >= eol + 3 + length then
      local msg = buf:sub(eol+2,eol+3+length)
      buf = buf:sub(eol+3+length+1)
      vim.schedule(function () self:on_message(msg) end)
      -- check again, very tailcall
      return on_stdout('')
    end
  end

  self.read_stop = self.stream_input:read_start(on_stdout)
end

function JSONRPCClient:on_message(data)
  local msg = vim.api.nvim_call_function('json_decode', {data})
  if msg.id ~= nil then
    local callback = self.callbacks[msg.id]
    if callback ~= nil then
      self.callbacks[msg.id] = nil
      callback(msg)
    else
      assert(false, "Orpah response")
    end
  else
    self.notifications:put(msg)
  end
end

function JSONRPCClient:send(msg)
  local bytes = vim.api.nvim_call_function('json_encode', {msg})
  local packet = 'Content-Length: ' .. bytes:len() ..'\r\n\r\n' ..bytes
  return self.stream_output:write(packet)
end

function JSONRPCClient:notify(method, params)
  local notification = {
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  }
  self:send(notification)
end

function JSONRPCClient:request(method, params)
  self.request_id = self.request_id + 1
  local request_id = self.request_id

  local response = async.Future:new()
  self.callbacks[request_id] = function(msg) response:put(msg) end

  local request = {
    jsonrpc = "2.0",
    method = method,
    params = params or {},
    id = request_id
  }
  self:send(request)

  return response
end

function JSONRPCClient:stop()
  self.notifications:close()
  self.read_stop()
  self.callbacks = nil
end

return {
  JSONRPCClient = JSONRPCClient
}
