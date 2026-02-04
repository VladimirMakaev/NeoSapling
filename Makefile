# NeoSapling Makefile
#
# Targets:
#   test   - Run all tests via plenary (clones plenary if needed)
#   clean  - Remove tmp directory (plenary clone)
#
# Usage:
#   make test              # Run all tests in tests/specs/
#   TEST_FILES=tests/specs/cli make test  # Run specific directory
#
# Notes:
#   - Tests run with 120s timeout to prevent hanging nvim --headless processes
#   - nvim --headless requires explicit exit (plenary handles this for tests)
#   - For manual nvim --headless scripts, always call vim.cmd('qa!') or os.exit()

.PHONY: test clean

# Timeout in seconds (default 120s, override with TIMEOUT=300 make test)
TIMEOUT ?= 120

# Clone plenary for testing
tmp/plenary:
	mkdir -p tmp
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim tmp/plenary

# Run tests in isolated nvim instance (with timeout to prevent hangs)
test: tmp/plenary
	@timeout $(TIMEOUT) env NVIM_APPNAME=neosapling-test nvim --headless --noplugin -u NONE -S tests/init.lua || \
		if [ $$? -eq 124 ]; then echo "ERROR: Tests timed out after $(TIMEOUT)s"; exit 1; fi

# Clean up
clean:
	rm -rf tmp
