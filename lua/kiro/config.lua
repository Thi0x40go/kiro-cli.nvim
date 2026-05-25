--- @class KiroKeymaps
--- @field close string key to close windows (default: "q")
--- @field approve string key to approve tool in popup (default: "a")
--- @field deny string key to deny tool in popup (default: "d")
--- @field view_diff string key to toggle diff preview (default: "v")
--- @field yank string key to yank agent response in chat (default: "y")
--- @field send_prompt string key to send prompt from input window (default: "<CR>")

--- @class KiroConfig
--- @field position "float"|"split" UI chat position
--- @field auto_approve_safe_tools boolean auto-approve read-only tools
--- @field allowed_tools string[] list of tools that can run without confirmation
--- @field hook_socket_path string path to Unix socket (or TCP port) for bridge communication
--- @field diff_preview_mode "unified"|"side-by-side" mode to show code diffs
--- @field keymaps KiroKeymaps customizable keyboard shortcuts
--- @field session_persistence boolean save and restore chat session histories
--- @field mcp_enabled boolean enable LSP/diagnostics/context exposure
--- @field kiro_cmd string command or path to Kiro CLI executable

local M = {}

--- @type KiroConfig
local DEFAULT_CONFIG = {
  position = "float",
  auto_approve_safe_tools = true,
  allowed_tools = {
    "read",
    "fs_read",
    "grep_search",
    "workspace_symbols",
    "ls",
    "git_status",
  },
  hook_socket_path = vim.fn.stdpath("run") .. "/kiro_bridge.sock",
  diff_preview_mode = "unified",
  keymaps = {
    close = "q",
    approve = "a",
    deny = "d",
    view_diff = "v",
    yank = "y",
    send_prompt = "<CR>",
  },
  session_persistence = true,
  mcp_enabled = true,
  kiro_cmd = "kiro-cli",
}

--- @type KiroConfig
M.values = {}

--- Setup and extend defaults with user options
--- @param opts? table
function M.setup(opts)
  -- If Windows or if run path doesn't exist, fall back to temp directory for socket
  if vim.fn.has("win32") == 1 then
    DEFAULT_CONFIG.hook_socket_path = "127.0.0.1:49999" -- Use TCP port on Windows
  elseif not vim.fn.isdirectory(vim.fn.stdpath("run")) or vim.fn.stdpath("run") == "" then
    DEFAULT_CONFIG.hook_socket_path = "/tmp/kiro_bridge.sock"
  end

  M.values = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})
end

return M
