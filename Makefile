# NeoSapling Makefile
#
# Targets:
#   test   - Run all tests via plenary (clones plenary if needed)
#   clean  - Remove tmp directory (plenary clone)
#
# Usage:
#   make test              # Run all tests in tests/specs/
#   TEST_FILES=tests/specs/cli make test  # Run specific directory

.PHONY: test clean

# Clone plenary for testing
tmp/plenary:
	mkdir -p tmp
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim tmp/plenary

# Run tests in isolated nvim instance
test: tmp/plenary
	NVIM_APPNAME=neosapling-test nvim --headless --noplugin -u NONE -S tests/init.lua

# Clean up
clean:
	rm -rf tmp
