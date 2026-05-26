# kiro.nvim

Neovim plugin for Kiro CLI integration via tmux popups.

## Requirements

- Neovim 0.8+
- tmux 3.2+
- [Kiro CLI](https://docs.aws.amazon.com/kiro/)

## Installation

### lazy.nvim

```lua
{
  'Thi0x40go/kiro-cli.nvim',
  config = function()
    require('kiro').setup()
  end,
  keys = {
    { '<leader>tk', '<cmd>KiroToggle<cr>', desc = 'Toggle Kiro CLI' },
    { '<leader>kd', '<cmd>KiroDebug<cr>', desc = 'Kiro Debug' },
    { '<leader>kc', '<cmd>KiroCleanup<cr>', desc = 'Kiro Cleanup' },
  },
}
```

## Configuration

```lua
require('kiro').setup({
  trust_all_tools = false,  -- Enable --trust-all-tools flag
  startup_timeout = 3000,   -- Startup wait time in ms
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:KiroToggle` | Toggle Kiro CLI popup |
| `:KiroDebug` | Show debug info |
| `:KiroCleanup` | Kill all Kiro sessions |

## Keymaps

Suggested keymaps (add to your config):

```lua
vim.keymap.set('n', '<leader>tk', '<cmd>KiroToggle<cr>', { desc = 'Toggle Kiro CLI' })
```

## Usage

1. Open Neovim inside tmux
2. Press `<leader>tk` to open Kiro CLI popup
3. Use your tmux prefix + `d` to close the popup (session persists)

## Tool Approvals (Security Gate)

`kiro-cli.nvim` provides a hook script to intercept Kiro CLI tool usage requests and prompt you for approval inside Neovim via a beautiful popup modal.

### 1. Configure the Hook in Kiro CLI

To register the hook, edit your Kiro CLI agent configuration file (e.g., `~/.kiro/agents/kiro_default.json` or create it if it doesn't exist) and add the `preToolUse` hook:

```json
{
  "hooks": {
    "preToolUse": "node /absolute/path/to/kiro-cli.nvim/hooks/approval.js"
  }
}
```

*(Replace `/absolute/path/to/kiro-cli.nvim` with the actual path to this plugin on your system)*

### 2. Neovim Configuration

Make sure `trust_all_tools` is set to `false` in your Neovim setup so that the hook is triggered instead of bypassing the approval modal:

```lua
require('kiro').setup({
  trust_all_tools = false,
})
```

## License

MIT
