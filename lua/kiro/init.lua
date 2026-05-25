--- Kiro CLI Neovim Integration Entry Point
--- Fully modular, asynchronous, production-grade integration

local M = {}

M.client = nil
M.pending_approval_callback = nil

--- Start the Kiro ACP client process singleton
--- @return KiroClient|nil
function M.start_client()
  if M.client and M.client.is_running then
    return M.client
  end

  local client_mod = require("kiro.acp.client")
  local chat = require("kiro.ui.chat")

  M.client = client_mod.Client.new(function(event_type, data)
    chat.handle_client_event(event_type, data)
  end)

  local started = M.client:start()
  if started then
    return M.client
  else
    M.client = nil
    return nil
  end
end

--- Toggles the floating / split chat window
function M.toggle()
  if not M.client or not M.client.is_running then
    M.start_client()
  end
  require("kiro.ui.chat").toggle()
end

--- Configure and initialize the plugin
--- @param opts? KiroConfig
function M.setup(opts)
  -- 1. Setup default configurations
  require("kiro.config").setup(opts)

  -- 2. Bind user commands (:KiroChat, :KiroFix, etc.)
  require("kiro.commands").setup()

  -- 3. Start TCP/Unix socket server for Kiro preToolUse/postToolUse hooks
  require("kiro.hooks.bridge").start()

  -- 4. Clean up processes and socket files on Neovim exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if M.client then
        M.client:close()
      end
      require("kiro.hooks.bridge").stop()
    end,
  })
end

return M
