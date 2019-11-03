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

local function _dofile(path)
  dofile(path.string)
end

local _string = {}

function _string.starts_with(v, prefix)
   return v:sub(1, #prefix) == prefix
end

function _string.lines(v, start, stop)
  assert(start == nil or start > 0)
  assert(stop == nil or stop > 1)
  local lines = v:gmatch("[^\r\n]+")
  local lnum = 1
  return function()
    if start ~= nil and lnum == 1 then
      while lnum < start do
        local _ = lines()
        lnum = lnum + 1
      end
    end
    if stop ~= nil and lnum > stop then
      return nil
    end
    local line = lines()
    lnum = lnum + 1
    return line
  end
end

local _iterator = {}

function _iterator.concat(it, sep)
  local res = ""
  local i = 1
  for v in it do
    if i == 1 then
      res = v
    else
      res = res .. sep .. v
    end
    i = i + 1
  end
  return res
end

local _table = {}

function _table.from_iterator(it)
  if type(it) == 'table' then
    return it
  end
  local res = {}
  for item in it do
    table.insert(res, item)
  end
  return res
end

function _table.concat(t, sep)
  local res = ""
  for i, v in ipairs(t) do
    if i == 1 then
      res = v
    else
      res = res .. sep .. v
    end
  end
  return res
end

function _table.map(t, f)
  local res = {}
  for _, v in ipairs(t) do
    table.insert(res, f(v))
  end
  return res
end

function _table.mapi(t, f)
  local res = {}
  for i, v in ipairs(t) do
    table.insert(res, f(v, i))
  end
  return res
end

function _table.is_array(t)
  return type(t) == 'table' and (#t > 0 or next(t) == nil)
end

return {
  string = _string,
  table = _table,
  iterator = _iterator,
  dofile = _dofile,
  Object = Object,
  LinkedList = LinkedList,
  table_pack = table_pack,
  array_copy = array_copy,
  errorf = errorf,
  error = error,
}
