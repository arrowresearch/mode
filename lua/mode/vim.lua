--
-- High level wrapper around neovim Lua API.
--

local util = require 'mode.util'

-- Proxy for convenient calls to vim functions.
--
-- Example (getting the current buffer filename):
--
--   local vim = require 'mode.vim'
--   local filename = vim.call.expand("%:p")

local call_meta = {
  __index = function(t, k)
    return function(...)
      local args = util.table_pack(...)
      wait()
      return vim.api.nvim_call_function(k, args)
    end
  end
}

local call = {}
setmetatable(call, call_meta)

-- Wait for VIM API to be available.
--
-- This assumes that if no coroutine is running then it's safe to call into vim.

function wait()
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

local function show(o)
  wait()
  print(vim.inspect(o))
end

return {
  call = call,
  wait = wait,
  show = show,
}
