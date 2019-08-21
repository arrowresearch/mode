local os = require 'os'
local table = require 'table'

local _M = {}
local _NAME = ... or 'test'

local slash = '/'
if os.getenv'OS'=='Windows_NT' then
	slash = '\\'
end

local newproxy = newproxy or function(proto)
	if proto==true then
		return setmetatable({}, {})
	elseif proto then
		return setmetatable({}, getmetatable(proto))
	else
		return {}
	end
end

local prototype = newproxy(true)
local data = setmetatable({}, {__mode='k'})
local mt = getmetatable(prototype)
local methods = {}
local getters = {}

local function new(this)
	local self = newproxy(prototype)
	data[self] = this
	return self
end

_M.empty = new{}

local type = type
function _M.type(value)
	return data[value] and 'path' or type(value)
end

function _M.split(s)
	if type(s)~='string' then error("bad argument #1 to split (string expected, got "..type(s)..")", 2) end
	local this = {}
	if s then
		local words = {}
		for word in s:gmatch('[^\\/]+') do
			table.insert(words, word)
		end
		if s:match('^\\\\') then
			this.root = 'UNC'
			this.absolute = true
			for i=1,#words do
				this[i] = words[i]
			end
		elseif s:match('^[\\/]') then
			this.root = nil
			this.absolute = true
			for i=1,#words do
				this[i] = words[i]
			end
		elseif #words==0 then
			return _M.empty
		elseif words[1]:match('^%a:$') then
			this.root = words[1]:upper()
			this.absolute = true
			for i=2,#words do
				this[i-1] = words[i]
			end
		elseif words[1]:match('^%a:') then
			-- split the root from first element
			this.root = words[1]:sub(1, 2)
			words[1] = words[1]:sub(3)
			this.absolute = nil
			for i=1,#words do
				this[i] = words[i]
			end
		else
			this.root = nil
			this.absolute = nil
			for i=1,#words do
				this[i] = words[i]
			end
		end
	end
	return new(this)
end

local function p2s(p, s)
	if p.root=='UNC' then
		s = s or '\\'
		return s..s..table.concat(p, s)
	else
		s = s or slash
		return (p.root or '')..(p.absolute and s or '')..table.concat(p, s)
	end
end

function mt:__index(k)
	local getter = getters[k]
	if getter then
		return getter(self)
	end
	local method = methods[k]
	if method then
		return method
	end
	local this = data[self]
	return this[k]
end

function getters:string()
	local this = data[self]
	return p2s(this)
end

function getters:ustring()
	local this = data[self]
	return p2s(this, '/')
end

function getters:wstring()
	local this = data[self]
	return p2s(this, '\\')
end

function methods:tostring(s)
	local this = data[self]
	return p2s(this, s)
end

function getters:file()
	local this = data[self]
	return this[#this]
end
getters.leaf = getters.file

function getters:parent()
	local this = data[self]
	if #this==0 then
		return nil
	else
		local p = {}
		p.root = this.root
		p.absolute = this.absolute
		for i=1,#this-1 do
			p[i] = this[i]
		end
		return new(p)
	end
end
-- :FIXME: remove compatibility stuff
getters.dir = getters.parent

function getters:relative()
	local this = data[self]
	return not this.absolute
end

function getters:canonical()
	local path = self:sub(0,0)
	for i=1,#self do
		local dir = self[i]
		if dir=='.' then
			-- ignore
		elseif dir=='..' and path[#path]~='..' then
			path = path.dir
			if not path then
				if self.relative then
					path = self:sub(0,0) / '..'
				else
					return nil
				end
			end
		else
			path = path / dir
		end
	end
	return path
end

function mt:__tostring()
	local this = data[self]
	return p2s(this)
end

function mt:__len()
	local this = data[self]
	return #this
end

function mt:__newindex(k, v)
	error("attempt to index a path value")
end

local ambiguous = {
	['  : '] = true,
	[':  /'] = true,
	[' /: '] = true,
	[':/: '] = true,
	[':/ /'] = true,
}

local function concat(self, other)
	if type(self)=='string' then
		self = _M.split(self)
	end
	if type(other)=='string' then
		other = _M.split(other)
	end
	local this,that = data[self],data[other]
	if not this or not that then error("attempt to concatenate a "..(this and "path" or type(self)).." with a "..(that and "path" or type(other)), 2) end
	local p = {}
	local case = (this.root and ':' or ' ')
		.. (this.absolute and '/' or ' ')
		.. (that.root and ':' or ' ')
		.. (that.absolute and '/' or ' ')
	if ambiguous[case] then error("ambiguous path concatenation", 2) end
	p.root = that.root or this.root
	p.absolute = that.absolute or this.absolute
	if (not that.root or this.root==that.root) and not that.absolute then
		for _,word in ipairs(this) do
			table.insert(p, word)
		end
	end
	for _,word in ipairs(that) do
		table.insert(p, word)
	end
	return new(p)
end

function mt:__div(other)
	return concat(self, other)
end
--[[
function mt:__concat(other)
	return concat(self, other)
end
--]]
function methods:sub(i, j)
	local this = data[self]
	local p = {}
	if i <= 0 then
		i = 1
		p.root = this.root
		p.absolute = this.absolute
	end
	if j == nil then j = #this end
	if j < 0 then j = #this + 1 + j end
	for k=i,j do
		table.insert(p, this[k])
	end
	return new(p)
end

function mt:__eq(other)
	local this = data[self]
	local that = data[other]
	local base = this and that
		and not this.absolute==not that.absolute -- these 'not' account for nil vs. false
		and this.root==that.root
		and #this==#that
	if not base then return false end
	for i=1,#this do
		if this[i]~=that[i] then return false end
	end
	return true
end

local pack = table.pack or function(...)
	return {n=select('#', ...), ...}
end
local unpack = table.unpack or unpack

local function wrapf(f, resultpath)
	if resultpath then
		return function(...)
			local args = pack(...)
			for i=1,args.n do
				if _M.type(args[i])=='path' then
					args[i] = tostring(args[i])
				end
			end
			local result = pack(f(unpack(args, 1, args.n)))
			for _,k in ipairs(resultpath) do
				result[k] = _M.split(result[k])
			end
			return unpack(result, 1, result.n)
		end
	else
		return function(...)
			local args = pack(...)
			for i=1,args.n do
				if _M.type(args[i])=='path' then
					args[i] = tostring(args[i])
				end
			end
			return f(unpack(args, 1, args.n))
		end
	end
end

_M.wrap = wrapf

local function wrapm(mod, resultpath, wrapped_functions)
	if not resultpath then resultpath = {} end
	local mod2 = {}
	for k,v in pairs(package.loaded) do
		if v==mod then
			package.loaded[k..'(path)'] = mod2
		end
	end
	for k,v in pairs(mod) do
		if type(v)=='function' and (not wrapped_functions or wrapped_functions[k]) then
			mod2[k] = wrapf(v, resultpath[k])
		else
			mod2[k] = v
		end
	end
	return mod2
end

local function wrapm_install(mod, resultpath, wrapped_functions)
	if not resultpath then resultpath = {} end
	local mod0 = {}
	for k,v in pairs(package.loaded) do
		if v==mod then
			package.loaded[k..'(nopath)'] = mod0
		end
	end
	for k,v in pairs(mod) do
		if type(v)=='function' and (not wrapped_functions or wrapped_functions[k]) then
			mod0[k] = v
			mod[k] = wrapf(v, resultpath[k])
		end
	end
end

local default_wrappings = {
	io = {},
	lfs = {currentdir = {1}},
	os = {tmpname = {1}},
	_G = {},
}
local default_wrapped_functions = {
	_G = {loadfile=true, dofile=true}
}

local installed = false
function _M.install()
	if not installed then
		for modname,resultpath in pairs(default_wrappings) do
			wrapm_install(require(modname), resultpath, default_wrapped_functions[modname])
		end
		installed = true
	end
end

function _M.require(modname, resultpath)
	resultpath = resultpath or default_wrappings[modname] or {}
	return wrapm(require(modname), resultpath, default_wrapped_functions[modname])
end

-- backward compatibility
_M.require_wrapped = _M.require

if _NAME=='test' then
	local function expect(expectation, value, ...)
		if value~=expectation then
			error("expectation failed! "..tostring(expectation).." expected, got "..tostring(value), 2)
		end
	end
	local split = _M.split
	
	local s = [[/foo/bar]]
	local p = split(s)
	expect(s:gsub('/', slash), p.string)
	expect(s:gsub('/', slash), tostring(p))
	expect(s, p.ustring)
	expect(s:gsub('/', '\\'), p.wstring)
	expect(nil, p.root)
	expect(true, p.absolute)
	expect(false, p.relative)
	expect(2, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect(nil, p[3])
	assert(p.parent)
	expect([[/foo]], p.parent.ustring)
	
	local s = [[/]]
	local p = split(s)
	assert(p ~= _M.empty)
	expect(s:gsub('/', slash), p.string)
	expect(s:gsub('/', slash), tostring(p))
	expect(s, p.ustring)
	expect(s:gsub('/', '\\'), p.wstring)
	expect(nil, p.root)
	expect(true, p.absolute)
	expect(false, p.relative)
	expect(0, #p)
	expect(nil, p[1])
	assert(not p.parent)
	
	local s = [[foo/bar/baz]]
	local p = split(s)
	expect(s:gsub('/', slash), p.string)
	expect(s:gsub('/', slash), tostring(p))
	expect(nil, p.root)
	expect(nil, p.absolute)
	expect(true, p.relative)
	expect(3, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect('baz', p[3])
	expect(nil, p[4])
	assert(p.parent)
	expect([[foo/bar]], p.parent.ustring)
	
	local s = [[C:\foo\bar]]
	local p = split(s)
	expect(s:gsub('\\', slash), p.string)
	expect(s:gsub('\\', slash), tostring(p))
	expect('C:', p.root)
	expect(true, p.absolute)
	expect(false, p.relative)
	expect(2, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect(nil, p[3])
	assert(p.parent)
	expect([[C:\foo]], p.parent.wstring)
	
	local s = [[C:\]]
	local p = split(s)
	expect(s:gsub('\\', slash), p.string)
	expect(s:gsub('\\', slash), tostring(p))
	expect('C:', p.root)
	expect(true, p.absolute)
	expect(false, p.relative)
	expect(0, #p)
	expect(nil, p[1])
	assert(not p.parent)
	
	local s = [[C:foo\bar]]
	local p = split(s)
	expect(s:gsub('\\', slash), p.string)
	expect(s:gsub('\\', slash), tostring(p))
	expect('C:', p.root)
	expect(nil, p.absolute)
	expect(true, p.relative)
	expect(2, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect(nil, p[3])
	assert(p.parent)
	expect([[C:foo]], p.parent.wstring)
	
	local s = [[\foo\bar]]
	local p = split(s)
	expect(s:gsub('\\', slash), p.string)
	expect(s:gsub('\\', slash), tostring(p))
	expect(nil, p.root)
	expect(true, p.absolute)
	expect(false, p.relative)
	expect(2, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect(nil, p[3])
	assert(p.parent)
	expect([[\foo]], p.parent.wstring)
	
	local s = [[\]]
	local p = split(s)
	expect(s:gsub('\\', slash), p.string)
	expect(s:gsub('\\', slash), tostring(p))
	expect(nil, p.root)
	expect(true, p.absolute)
	expect(false, p.relative)
	expect(0, #p)
	expect(nil, p[1])
	assert(not p.parent)
	
	local s = [[foo\bar]]
	local p = split(s)
	expect(s:gsub('\\', slash), p.string)
	expect(s:gsub('\\', slash), tostring(p))
	expect(nil, p.root)
	expect(nil, p.absolute)
	expect(true, p.relative)
	expect(2, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect(nil, p[3])
	assert(p.parent)
	expect([[foo]], p.parent.wstring)
	
	local s = [[\\foo\bar]]
	local p = split(s)
	expect(s, p.string) --  UNC paths use backslash only
	expect(s, tostring(p)) --  UNC paths use backslash only
	expect('UNC', p.root)
	expect(true, p.absolute)
	expect(false, p.relative)
	expect(2, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect(nil, p[3])
	assert(p.parent)
	expect([[\\foo]], p.parent.wstring)
	
	local s = [[\\]]
	local p = split(s)
	expect(s, p.string) --  UNC paths use backslash only
	expect(s, tostring(p)) --  UNC paths use backslash only
	expect('UNC', p.root)
	expect(true, p.absolute)
	expect(false, p.relative)
	expect(0, #p)
	expect(nil, p[1])
	assert(not p.parent)
	
	local s1,s2 = [[foo/bar]],[[baz/baf]]
	local p1,p2 = split(s1),split(s2)
	local p = p1 / p2
	expect(s1:gsub('/', slash)..slash..s2:gsub('/', slash), p.string)
	expect(s1:gsub('/', slash)..slash..s2:gsub('/', slash), tostring(p))
	expect(nil, p.root)
	expect(nil, p.absolute)
	expect(4, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect('baz', p[3])
	expect('baf', p[4])
	expect(nil, p[5])
	assert(p.parent)
	expect([[foo/bar/baz]], p.parent.ustring)
	
	local s1,s2 = [[/foo/bar]],[[baz/baf]]
	local p1,p2 = split(s1),split(s2)
	local p = p1 / p2
	expect(s1:gsub('/', slash)..slash..s2:gsub('/', slash), p.string)
	expect(s1:gsub('/', slash)..slash..s2:gsub('/', slash), tostring(p))
	expect(nil, p.root)
	expect(true, p.absolute)
	expect(4, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect('baz', p[3])
	expect('baf', p[4])
	expect(nil, p[5])
	assert(p.parent)
	expect([[/foo/bar/baz]], p.parent.ustring)
	
	local s1,s2 = [[foo/bar]],[[/baz/baf]]
	local p1,p2 = split(s1),split(s2)
	local p = p1 / p2
	expect(s2:gsub('/', slash), p.string)
	expect(s2:gsub('/', slash), tostring(p))
	expect(nil, p.root)
	expect(true, p.absolute)
	expect(2, #p)
	expect('baz', p[1])
	expect('baf', p[2])
	expect(nil, p[3])
	assert(p.parent)
	expect([[/baz]], p.parent.ustring)
	
	local s1,s2 = [[/foo/bar]],[[/baz/baf]]
	local p1,p2 = split(s1),split(s2)
	local p = p1 / p2
	expect(s2:gsub('/', slash), p.string)
	expect(s2:gsub('/', slash), tostring(p))
	expect(nil, p.root)
	expect(true, p.absolute)
	expect(2, #p)
	expect('baz', p[1])
	expect('baf', p[2])
	expect(nil, p[3])
	assert(p.parent)
	expect([[/baz]], p.parent.ustring)
	
	local s1,s2 = [[foo\bar]],[[baz\baf]]
	local p1,p2 = split(s1),split(s2)
	local p = p1 / p2
	expect(s1:gsub('\\', slash)..slash..s2:gsub('\\', slash), p.string)
	expect(s1:gsub('\\', slash)..slash..s2:gsub('\\', slash), tostring(p))
	expect(nil, p.root)
	expect(nil, p.absolute)
	expect(4, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect('baz', p[3])
	expect('baf', p[4])
	expect(nil, p[5])
	assert(p.parent)
	expect([[foo\bar\baz]], p.parent.wstring)
	
	local s1,s2 = [[\foo\bar]],[[baz\baf]]
	local p1,p2 = split(s1),split(s2)
	local p = p1 / p2
	expect(s1:gsub('\\', slash)..slash..s2:gsub('\\', slash), p.string)
	expect(s1:gsub('\\', slash)..slash..s2:gsub('\\', slash), tostring(p))
	expect(nil, p.root)
	expect(true, p.absolute)
	expect(4, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect('baz', p[3])
	expect('baf', p[4])
	expect(nil, p[5])
	assert(p.parent)
	expect([[\foo\bar\baz]], p.parent.wstring)
	
	local s1,s2 = [[foo\bar]],[[\baz\baf]]
	local p1,p2 = split(s1),split(s2)
	local p = p1 / p2
	expect(s2:gsub('\\', slash), p.string)
	expect(s2:gsub('\\', slash), tostring(p))
	expect(nil, p.root)
	expect(true, p.absolute)
	expect(2, #p)
	expect('baz', p[1])
	expect('baf', p[2])
	expect(nil, p[3])
	assert(p.parent)
	expect([[\baz]], p.parent.wstring)
	
	local s1,s2 = [[\foo\bar]],[[\baz\baf]]
	local p1,p2 = split(s1),split(s2)
	local p = p1 / p2
	expect(s2:gsub('\\', slash), p.string)
	expect(s2:gsub('\\', slash), tostring(p))
	expect(nil, p.root)
	expect(true, p.absolute)
	expect(2, #p)
	expect('baz', p[1])
	expect('baf', p[2])
	expect(nil, p[3])
	assert(p.parent)
	expect([[\baz]], p.parent.wstring)
	
	local s1,s2 = [[C:\foo\bar]],[[baz\baf]]
	local p1,p2 = split(s1),split(s2)
	local p = p1 / p2
	expect(s1:gsub('\\', slash)..slash..s2:gsub('\\', slash), p.string)
	expect(s1:gsub('\\', slash)..slash..s2:gsub('\\', slash), tostring(p))
	expect('C:', p.root)
	expect(true, p.absolute)
	expect(4, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect('baz', p[3])
	expect('baf', p[4])
	expect(nil, p[5])
	assert(p.parent)
	expect([[C:\foo\bar\baz]], p.parent.wstring)
	
	local s1,s2 = [[C:foo\bar]],[[baz\baf]]
	local p1,p2 = split(s1),split(s2)
	local p = p1 / p2
	expect(s1:gsub('\\', slash)..slash..s2:gsub('\\', slash), p.string)
	expect(s1:gsub('\\', slash)..slash..s2:gsub('\\', slash), tostring(p))
	expect('C:', p.root)
	expect(nil, p.absolute)
	expect(4, #p)
	expect('foo', p[1])
	expect('bar', p[2])
	expect('baz', p[3])
	expect('baf', p[4])
	expect(nil, p[5])
	assert(p.parent)
	expect([[C:foo\bar\baz]], p.parent.wstring)
	
	local s1,s2 = [[C:foo\bar]],[[\baz\baf]]
	local p1,p2 = split(s1),split(s2)
	assert(not pcall(function() return p1 / p2 end))
	assert(select(2, pcall(function() return p1 / p2 end)):match(': ambiguous path concatenation$'))
	
	local s1,s2 = [[foo\bar]],[[D:\baz\baf]]
	local p1,p2 = split(s1),split(s2)
	local p = p1 / p2
	expect(s2:gsub('\\', slash), p.string)
	expect(s2:gsub('\\', slash), tostring(p))
	expect('D:', p.root)
	expect(true, p.absolute)
	expect(2, #p)
	expect('baz', p[1])
	expect('baf', p[2])
	expect(nil, p[3])
	assert(p.parent)
	expect([[D:\baz]], p.parent.wstring)
	
	local s1,s2 = [[C:\foo\bar]],[[D:\baz\baf]]
	local p1,p2 = split(s1),split(s2)
	local p = p1 / p2
	expect(s2:gsub('\\', slash), p.string)
	expect(s2:gsub('\\', slash), tostring(p))
	expect('D:', p.root)
	expect(true, p.absolute)
	expect(2, #p)
	expect('baz', p[1])
	expect('baf', p[2])
	expect(nil, p[3])
	assert(p.parent)
	expect([[D:\baz]], p.parent.wstring)
	
	local s1,s2 = [[C:\foo\bar]],[[D:\baz\baf]]
	local p1,p2 = split(s1),split(s2)
	expect([[C:\]], p1:sub(0, 0).wstring)
	expect([[foo]], p1:sub(1, 1).wstring)
	expect([[foo/bar]], p1:sub(1, 2).ustring)
	expect([[baz/baf]], p2:sub(1).ustring)
	expect([[D:/baz]], p2:sub(0,1).ustring)
	expect([[baz/baf]], p2:sub(1, -1).ustring)
	expect([[baz]], p2:sub(1, -2).ustring)
	
	expect('foo/bar',    (split'foo'    / split'bar'   ).ustring)
--	expect('???',        (split'foo'    / split'D:bar' ).ustring) -- ambiguous D:foo/bar or D:bar
	expect('/bar',       (split'foo'    / split'/bar'  ).ustring)
	expect('D:/bar',     (split'foo'    / split'D:/bar').ustring)
	expect('C:foo/bar',  (split'C:foo'  / split'bar'   ).ustring)
	expect('D:bar',      (split'C:foo'  / split'D:bar' ).ustring)
--	expect('???',        (split'C:foo'  / split'/bar'  ).ustring) -- ambiguous C:/bar or /bar
	expect('D:/bar',     (split'C:foo'  / split'D:/bar').ustring)
	expect('/foo/bar',   (split'/foo'   / split'bar'   ).ustring)
--	expect('???',        (split'/foo'   / split'D:bar' ).ustring) -- ambiguous D:/foo/bar or D:bar
	expect('/bar',       (split'/foo'   / split'/bar'  ).ustring)
	expect('D:/bar',     (split'/foo'   / split'D:/bar').ustring)
	expect('C:/foo/bar', (split'C:/foo' / split'bar'   ).ustring)
--	expect('???',        (split'C:/foo' / split'D:bar' ).ustring) -- ambiguous D:/foo/bar or D:bar
--	expect('???',        (split'C:/foo' / split'/bar'  ).ustring) -- ambiguous C:/bar or /bar
	expect('D:/bar',     (split'C:/foo' / split'D:/bar').ustring)
	
	assert(not pcall(function() return split'foo'    / split'D:bar' end))
	assert(select(2, pcall(function() return split'foo'    / split'D:bar' end)):match(': ambiguous path concatenation$'))
	assert(not pcall(function() return split'C:foo'  / split'/bar'  end))
	assert(select(2, pcall(function() return split'C:foo'  / split'/bar'  end)):match(': ambiguous path concatenation$'))
	assert(not pcall(function() return split'/foo'   / split'D:bar' end))
	assert(select(2, pcall(function() return split'/foo'   / split'D:bar' end)):match(': ambiguous path concatenation$'))
	assert(not pcall(function() return split'C:/foo' / split'D:bar' end))
	assert(select(2, pcall(function() return split'C:/foo' / split'D:bar' end)):match(': ambiguous path concatenation$'))
	assert(not pcall(function() return split'C:/foo' / split'/bar'  end))
	assert(select(2, pcall(function() return split'C:/foo' / split'/bar'  end)):match(': ambiguous path concatenation$'))
	
	expect([[foo\bar]],   (split[[foo]]   / split[[bar]]  ).wstring)
	expect([[\bar]],      (split[[foo]]   / split[[\bar]] ).wstring)
	expect([[\\bar]],     (split[[foo]]   / split[[\\bar]]).wstring)
	expect([[\foo\bar]],  (split[[\foo]]  / split[[bar]]  ).wstring)
	expect([[\bar]],      (split[[\foo]]  / split[[\bar]] ).wstring)
	expect([[\\bar]],     (split[[\foo]]  / split[[\\bar]]).wstring)
	expect([[\\foo\bar]], (split[[\\foo]] / split[[bar]]  ).wstring)
--	expect([[???]],       (split[[\\foo]] / split[[\bar]] ).wstring) -- ambiguous \\bar or \bar
	expect([[\\bar]],     (split[[\\foo]] / split[[\\bar]]).wstring)
	
	expect([[foo\bar]],   (     [[foo]]   / split[[bar]]  ).wstring)
	expect([[foo\bar]],   (split[[foo]]   /      [[bar]]  ).wstring)
	
	assert(not pcall(function() return split[[\\foo]] / split[[\bar]] end))
	assert(select(2, pcall(function() return split[[\\foo]] / split[[\bar]] end)):match(': ambiguous path concatenation$'))

	expect('path', _M.type(split''))
	
	assert(_M.empty)
	expect('path', _M.type(_M.empty))
	expect('', _M.empty.string)
	
	local p = split('')
	expect('', p.string)
	assert(p==_M.empty)
	
	local p1 = split[[foo/bar]]
	local p2 = split[[foo/bar]]
	assert(p1 == p2)
	
	expect('foo/bob', split('foo/bar/../bar/./baz/../../bob').canonical.ustring)
	expect('../../bob', split('../foo/bar/.././../../bob').canonical.ustring)
	expect(nil, split('/foo/bar/.././../..').canonical)
	expect('..', split('foo/bar/.././../..').canonical.ustring)

	print "all tests succeeded"
end

return _M
