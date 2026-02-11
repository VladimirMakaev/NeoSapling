# NeoSapling

Sapling VCS integration for Neovim -- a Magit/Neogit-style interface for the [Sapling](https://sapling-scm.com/) source control system.

## Features

- **Status view** (`:NeoSapling`) -- staged/unstaged files, commit graph, file diffs
- **Smartlog view** (`:NeoSaplingLog`) -- interactive commit tree with graph visualization
- **Commit workflow** -- commit, amend, absorb from within Neovim
- **Stack operations** -- rebase, hide, goto commits
- **File actions** -- stage, unstage, discard changes, hunk-level revert
- **Auto-refresh** via Watchman file watching (when available)
- **diffview.nvim integration** (optional) for enhanced diffs

## Requirements

- Neovim >= 0.9
- [Sapling VCS](https://sapling-scm.com/) (`sl` CLI) installed and on PATH
- Optional: [Watchman](https://facebook.github.io/watchman/) (for auto-refresh on file changes)
- Optional: [diffview.nvim](https://github.com/sindrets/diffview.nvim) (for enhanced diff viewing)

## Installation

### lazy.nvim

```lua
{
  "vmakaev/NeoSapling",
  cmd = { "NeoSapling", "NeoSaplingLog" },
  config = function()
    require("neosapling").setup({})
  end,
}
```

### packer.nvim

```lua
use {
  "vmakaev/NeoSapling",
  config = function()
    require("neosapling").setup({})
  end,
}
```

### Manual

Clone the repository into your Neovim packages directory:

```bash
git clone https://github.com/vmakaev/NeoSapling.git \
  ~/.local/share/nvim/site/pack/plugins/start/NeoSapling
```

Then add to your `init.lua`:

```lua
require("neosapling").setup({})
```

## Configuration

Below is the default configuration. All values are optional -- pass only what you want to override:

```lua
require("neosapling").setup({
  mappings = {
    status = {
      ["?"] = "help",
      ["c"] = "commit",
      ["q"] = "close",
      ["<Tab>"] = "toggle_fold",
    },
  },
  popup = {
    border = "rounded",
  },
  signs = {
    modified = "M",
    added = "A",
    removed = "R",
    untracked = "?",
  },
})
```

## Usage

| Command | Description |
|---------|-------------|
| `:NeoSapling` | Open the status view |
| `:NeoSaplingLog` | Open the smartlog view |

## Keybindings

### Status View

| Key | Action |
|-----|--------|
| `c` | Open commit popup |
| `s` | Stage file |
| `u` | Unstage file |
| `x` | Discard changes / revert hunk |
| `d` | Show diff (file diff in split, commit diff in popup) |
| `p` | Pull |
| `a` | Amend |
| `A` | Absorb |
| `Tab` | Toggle fold |
| `J` / `K` | Next / previous commit |
| `{` / `}` | Previous / next section |
| `?` | Help popup |
| `q` | Close |

### Smartlog View

| Key | Action |
|-----|--------|
| `c` | Open commit popup |
| `d` | Show commit diff |
| `H` | Hide commit |
| `r` | Rebase |
| `p` | Pull |
| `Enter` | Goto commit |
| `J` / `K` | Next / previous commit |
| `?` | Help popup |
| `q` | Close |

## Development

```bash
# Run tests
make test

# Run specific test file
TEST_FILES=tests/specs/cli make test

# Clean test artifacts
make clean
```

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) and run in an isolated Neovim instance (`NVIM_APPNAME=neosapling-test`).

## License

MIT
