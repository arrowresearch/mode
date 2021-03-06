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
  local waiting_len = nil

  local function parse_headers(data)
    local headers = {}
    for line in string.gmatch(data, "[^\r\n]+") do
      local colon = string.find(line, ":")
      if colon ~= nil then
        local name = util.string.trim(line:sub(1, colon - 1):lower())
        local value = util.string.trim(line:sub(colon + 1))
        headers[name] = value
      end
    end
    local len = headers['content-length']
    assert(len, 'Missing `Content-Length` header')
    return headers, tonumber(len)
  end

  local function on_stdout(chunk)
    if not chunk then
      return
    end
    buf = buf .. chunk

    if waiting_len == nil then
      -- wait for \r\n\r\n which separates headers and body
      local start, finish = string.find(buf, '\r\n\r\n')
      if not start then
        return
      end

      local _, len = parse_headers(string.sub(buf, 1, start + 1))
      buf = string.sub(buf, finish + 1)
      waiting_len = len
      return on_stdout('')
    else
      if string.len(buf) >= waiting_len then
        local msg = string.sub(buf, 1, waiting_len)
        buf = string.sub(buf, waiting_len + 1)
        waiting_len = nil
        vim.schedule(function () self:on_message(msg) end)
        return on_stdout('') -- check again
      end
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
