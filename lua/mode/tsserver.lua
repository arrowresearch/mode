local util = require 'mode.util'
local logging = require 'mode.logging'
local uv = require 'mode.uv'
local async = require 'mode.async'
local jsonrpc = require 'mode.jsonrpc'
local Diagnostics = require 'mode.diagnostics'

local TSServer = util.Object:extend()

TSServer.type = "tsserver"

function TSServer:init(o)
  self.log = logging.get_logger("tsserver")
  self.jsonrpc = o.jsonrpc
  self.root = o.root

  self.buffers = {}
  self.is_insert_mode = false

  self.on_shutdown = async.Channel:new()
end

function TSServer:did_open(buffer)
end

function TSServer:did_close(buffer)
end

function TSServer:did_change(change)
end

function TSServer:did_insert_enter(_)
  self.is_insert_mode = true
end

function TSServer:did_insert_leave(_)
  self.is_insert_mode = false
  Diagnostics:update()
end

function TSServer.did_buffer_enter(_) end

function TSServer:start(config)
  local proc = uv.spawn {
    cmd = config.cmd,
    args = config.args
  }

  local client = self:new {
    root = config.root,
    jsonrpc = jsonrpc.JSONRPCClient:new {
      stream_input = proc.stdout,
      stream_output = proc.stdin
    }
  }

  client.on_shutdown:subscribe(function()
    proc:shutdown()
  end)

  return client
end

function TSServer:shutdown()
  self.on_shutdown:put()
end

return {
  TSServer = TSServer,
}
