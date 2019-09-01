# NVIM_PROG = ../neovim/build/bin/nvim
NVIM_PROG = nvim
CHECK_EXCLUDE = lua/mode/path.lua

.PHONY: check
check:
	@luacheck lua --exclude-files $(CHECK_EXCLUDE)

.PHONY: test
test:
	@$(NVIM_PROG) \
		--headless -u NONE --noplugin --clean \
		+'verbose luafile ./test/setup.lua' \
		+'verbose luafile ./test/test_luacheck.lua'
