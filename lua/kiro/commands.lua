local M = {}

--- Command based approvals shortcut trigger
--- @param approved boolean
function M.handle_pending_approval(approved)
  local kiro = require("kiro")
  if kiro.pending_approval_callback then
    local cb = kiro.pending_approval_callback
    kiro.pending_approval_callback = nil
    cb(approved)
    vim.notify("[Kiro] Pending approval decision sent: " .. (approved and "Approved" or "Denied"), vim.log.levels.INFO)
  else
    vim.notify("[Kiro] No pending tool executions to approve or reject.", vim.log.levels.WARN)
  end
end

--- Setup and bind user commands in Neovim
function M.setup()
  local cmd = vim.api.nvim_create_user_command

  -- Toggle the snacks terminal chat
  cmd("KiroToggle", function() require("kiro").toggle({ position = "float" }) end, {})
  cmd("KiroChat", function() require("kiro").toggle({ position = "float" }) end, {})
  cmd("Kiro", function() require("kiro").toggle({ position = "float" }) end, {})
  cmd("KiroSplit", function() require("kiro").toggle({ position = "bottom" }) end, {})

  -- Hook decision overrides
  cmd("KiroApprove", function() M.handle_pending_approval(true) end, {})
  cmd("KiroReject", function() M.handle_pending_approval(false) end, {})
end

return M
