CHECK_EXCLUDE = lua/mode/path.lua
check:
	@luacheck lua --exclude-files $(CHECK_EXCLUDE)
