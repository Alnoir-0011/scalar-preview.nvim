PLENARY_DIR := .tests/plenary.nvim
# Pin to a known commit (nvim-lua/plenary.nvim@master as of 2026-10-05) instead of tracking
# master unpinned, since that test-runner code executes unsandboxed inside the test nvim.
PLENARY_REV := 74b06c6c75e4eeb3108ec01852001636d85a932b

.PHONY: test
test: $(PLENARY_DIR)/.git
	XDG_STATE_HOME=$(CURDIR)/.tests/state nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"

# Depend on .git (not the directory itself) so a clone that died partway through - leaving
# the directory present but incomplete - is retried instead of silently reused.
$(PLENARY_DIR)/.git:
	rm -rf $(PLENARY_DIR)
	git clone --filter=blob:none https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR)
	git -C $(PLENARY_DIR) checkout --quiet $(PLENARY_REV)

.PHONY: clean
clean:
	rm -rf .tests
