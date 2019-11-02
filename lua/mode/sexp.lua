local util = require 'mode.util'

local function chars(str)
  local idx = 1
  local next = function()
    local byte = str:byte(idx)
    idx = idx + 1
    if byte == nil then
      return nil
    end
    return string.char(byte)
  end
  local peek = function()
    local byte = str:byte(idx)
    if byte == nil then
      return nil
    end
    return string.char(byte)
  end
  return {next = next, peek = peek}
end

local function is_whitespace(c)
  return c == ' ' or c == '\t' or c == '\n' or c == '\r'
end

local function is_digit(c)
  return c:find('%d') ~= nil
end

local function parse_string(state)
  local res = ""
  local escape = false
  while true do
    local c = state.next()
    if c == nil or (c == '"' and not escape) then
      break
    elseif c == 'n' and escape then
      escape = false
      res = res .. '\n'
    elseif c == 'r' and escape then
      escape = false
      res = res .. '\r'
    elseif c == 't' and escape then
      escape = false
      res = res .. '\t'
    elseif c == '\\' and escape then
      escape = false
      res = res .. '\\'
    elseif c == '\\' then
      escape = true
    else
      escape = false
      res = res .. c
    end
  end
  return res
end

local function parse_number(state)
  local res = ""
  while true do
    local c = state.peek()
    if is_digit(c) then
      state.next()
      res = res .. c
    else
      break
    end
  end
  return tonumber(res)
end

local function parse_atom(state)
  local res = ""
  while true do
    local c = state.peek()
    if c == nil or is_whitespace(c) or c == '(' or c == ')' or c == '"' then
      break
    else
      state.next()
      res = res .. c
    end
  end
  return res
end

local parse_list, parse_expr

function parse_expr(state)
  local c = state.peek()
  if c == nil then
    error("error parsing s-expr")
  elseif c == '(' then
    state.next()
    return parse_list(state)
  elseif c == '"' then
    state.next()
    return parse_string(state)
  elseif is_digit(c) then
    return parse_number(state)
  else
    return parse_atom(state)
  end
end

function parse_list(state)
  local res = {}
  while true do
    local c = state.peek()
    if c == nil then
      error("error parsing list")
    elseif c == ')' then
      state.next()
      break
    elseif is_whitespace(c) then
      state.next()
    else
      table.insert(res, parse_expr(state))
    end
  end
  return res
end

local function parse(str)
  return parse_expr(chars(str))
end

local function to_table(sexpr)
  local res = {}
  for _, item in ipairs(sexpr) do
    assert(type(item) == 'table' and #item == 2)
    local k, v = item[1], item[2]
    res[k] = v
  end
  return res
end

local function of_table(t)
  local res = {}
  for k, v in pairs(t) do
    assert(type(k) == 'string', 'expected string as key')
    if v ~= nil then
      table.insert(res, {k, v})
    end
  end
  return res
end

local function quote(str)
  if str:find('[%s"]') then
    str = str:gsub("\"", '\\"')
    str = str:gsub("\n", '\\n')
    str = str:gsub("\r", '\\r')
    str = str:gsub("\t", '\\t')
    return '"' .. str .. '"'
  else
    return str
  end
end

local function print(sexpr)
  local t_sexpr = type(sexpr)
  if t_sexpr == "table" then
    local inner = {}
    for _, v in ipairs(sexpr) do
      table.insert(inner, print(v))
    end
    inner = util.table.concat(inner, " ")
    return "(" .. inner .. ")"
  elseif t_sexpr == "string" then
    return quote(sexpr)
  elseif t_sexpr == "number" then
    return tostring(sexpr)
  elseif t_sexpr == "boolean" then
    return tostring(sexpr)
  elseif t_sexpr == "nil" then
    return "()"
  end
end

return {
  parse = parse,
  print = print,
  to_table = to_table,
  of_table = of_table,
}
