--- Kiro CLI Neovim Integration
--- Terminal Toggle + Hook Approval Security Gate

local M = {}

M.pending_approval_callback = nil

--- Toggle the Kiro CLI chat inside a snacks.nvim terminal
--- @param opts? table options like { position = "float" | "bottom" }
function M.toggle(opts)
  opts = opts or {}
  local position = opts.position or "float"

  local cmd = "kiro-cli chat"
  if require("kiro.config").values.trust_all_tools then
    cmd = cmd .. " --trust-all-tools"
  end

  if pcall(require, "snacks") then
    require("snacks").terminal.toggle(cmd, {
      win = {
        position = position,
        title = " Kiro CLI ",
      },
    })
  else
    vim.notify("Plugin 'snacks.nvim' not found. It is required to toggle the floating terminal.", vim.log.levels.ERROR)
  end
end

--- Configure and initialize the plugin
--- @param opts? KiroConfig
function M.setup(opts)
  -- 1. Setup config
  require("kiro.config").setup(opts)

  -- 2. Bind user commands (:KiroToggle, :KiroSplit, :KiroApprove, :KiroReject)
  require("kiro.commands").setup()

  -- 3. Start Unix/TCP socket server for external Kiro hooks
  require("kiro.hooks.bridge").start()

  -- 4. Teardown bridge server gracefully on Neovim exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      require("kiro.hooks.bridge").stop()
    end,
  })
end

return M
