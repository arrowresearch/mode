local uv = require 'mode.uv'
local path = require 'mode.path'

local exports = {}

--- Check if path exists
function exports.cwd()
  return path.split(uv._uv.cwd())
end

--- Check if path exists
function exports.exists(p)
  local stat, _ = uv._uv.fs_stat(p.string)
  return stat ~= nil
end

--- Finds closest ancestor path which conforms to a predicate
function exports.find_closest_ancestor(p, predicate)
  if predicate(p) then
    return p
  end

  local nextp = p.parent
  if nextp == nil then
    return nil
  else
    return exports.find_closest_ancestor(nextp, predicate)
  end
end

return exports
