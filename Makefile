NVIM_PROG = ../neovim/build/bin/nvim
# NVIM_PROG = nvim
CHECK_EXCLUDE = lua/mode/path.lua
TESTS = $(shell find test -name 'test_*.lua')

.PHONY: check
check:
	@luacheck lua --exclude-files $(CHECK_EXCLUDE)

.PHONY: test
test: $(TESTS:%=%.run)
test/test_%.lua.run: test/test_%.lua
	@NVIM_PROG=$(NVIM_PROG) test/runtest $(<)
