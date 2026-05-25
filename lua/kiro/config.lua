--- @class KiroKeymaps
--- @field close string key to close windows (default: "q")
--- @field approve string key to approve tool in popup (default: "a")
--- @field deny string key to deny tool in popup (default: "d")
--- @field view_diff string key to toggle diff preview (default: "v")

--- @class KiroConfig
--- @field trust_all_tools boolean bypass hook approval entirely
--- @field auto_approve_safe_tools boolean auto-approve read-only tools
--- @field allowed_tools string[] list of tools that can run without confirmation
--- @field hook_socket_path string path to Unix socket (or TCP port) for bridge communication
--- @field diff_preview_mode "unified"|"side-by-side" mode to show code diffs
--- @field keymaps KiroKeymaps customizable keyboard shortcuts

local M = {}

--- @type KiroConfig
local DEFAULT_CONFIG = {
  trust_all_tools = true,
  auto_approve_safe_tools = true,
  allowed_tools = {
    "read",
    "fs_read",
    "grep_search",
    "workspace_symbols",
    "ls",
    "git_status",
  },
  hook_socket_path = "/tmp/kiro_bridge.sock",
  diff_preview_mode = "side-by-side",
  keymaps = {
    close = "q",
    approve = "a",
    deny = "d",
    view_diff = "v",
  },
}

--- @type KiroConfig
M.values = {}

--- Setup and extend defaults with user options
--- @param opts? table
function M.setup(opts)
  -- If Windows, fall back to TCP port
  if vim.fn.has("win32") == 1 then
    DEFAULT_CONFIG.hook_socket_path = "127.0.0.1:49999"
  end

  M.values = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})
end

return M
