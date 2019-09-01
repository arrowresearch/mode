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
local function table_pack(...)
  local n = select('#', ...)
  local t = {...}
  for i = 1,n do
    if t[i] == nil then
      t[i] = NIL
    end
  end
  return t
end

local function table_is_array(t)
  return type(t) == 'table' and (#t > 0 or next(t) == nil)
end

local function array_copy(t)
  local copy = {}
  for i, v in ipairs(t) do
    copy[i] = v
  end
  return copy
end

local function errorf(msg, ...)
  error(string.format(msg, ...), 2)
end

return {
  Object = Object,
  LinkedList = LinkedList,
  table_pack = table_pack,
  table_is_array = table_is_array,
  array_copy = array_copy,
  errorf = errorf,
  error = error,
}
