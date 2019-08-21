--
-- Core Lua utilities.
--

-- Object
--
-- Simplistic object system for Lua.

local Object = {}
Object.__index = Object

function Object:new(o)
  local instance = {}
  setmetatable(instance, self)
  instance:init(o)
  return instance
end

function Object:extend()
  local cls = self:new()
  cls.__index = cls
  return cls
end

function Object.init(_) end

-- Mutable Linked List

local LinkedList = {empty = nil}

function LinkedList.add(list, value)
  return {value = value, next = list}
end

function LinkedList.remove(list, value)
  local prev = nil
  local current = list

  while current do
    if current.value == value then
      if prev then
        prev.next = current.next
        current.next = nil
        -- We've mutated some intermediate mode in-place, return same head.
        return list
      else
        -- Found element is the previous head, return new head.
        return current.next
      end
      break
    end
    prev = current
    current = current.next
  end
  -- Element wasn't found, return list as-is.
  return list
end

-- table.pack which works in older Lua

local NIL = {}
function table_pack(...)
  local n = select('#', ...)
  local t = {...}
  for i = 1,n do
    if t[i] == nil then
      t[i] = NIL
    end
  end
  return t
end


return {
  Object = Object,
  LinkedList = LinkedList,
  table_pack = table_pack,
}
