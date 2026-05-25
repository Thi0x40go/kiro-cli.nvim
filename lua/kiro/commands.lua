local chat = require("kiro.ui.chat")
local mcp = require("kiro.mcp")

local M = {}

--- Retrieve selection text if in visual mode
--- @return string|nil
local function get_visual_selection()
  -- If we are in visual mode, we must leave it to register marks '< and '>
  local mode = vim.api.nvim_get_mode().mode
  if mode:match("^[vV]") or mode == "\22" then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<ESC>", true, false, true), "x", true)
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    return table.concat(lines, "\n")
  end
  return nil
end

--- Execute a prompt by opening the chat window and submitting it
--- @param prompt string
local function execute_prompt(prompt)
  -- If chat is not open, open it
  local out_buf = vim.api.nvim_get_current_buf()
  chat.toggle() -- Open chat windows

  -- Locate input window buffer and write prompt
  vim.schedule(function()
    local in_buf = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match("Prompt Input") or vim.bo[buf].filetype == "markdown" and vim.api.nvim_win_get_height(win) <= 5 then
        in_buf = buf
        break
      end
    end

    if in_buf then
      vim.api.nvim_buf_set_lines(in_buf, 0, -1, false, vim.split(prompt, "\n"))
      chat.submit_prompt()
    end
  end)
end

--- `:KiroExplain` command handler
function M.explain()
  local selection = get_visual_selection()
  local filename, content = mcp.get_current_buffer()

  local prompt = ""
  if selection and selection ~= "" then
    prompt = string.format("Explain the following selected code from `%s`:\n\n```%s\n%s\n```", filename, vim.bo.filetype, selection)
  else
    prompt = string.format("Explain the code in the current buffer `%s`:\n\n```%s\n%s\n```", filename, vim.bo.filetype, content)
  end

  execute_prompt(prompt)
end

--- `:KiroRefactor` command handler
function M.refactor()
  local selection = get_visual_selection()
  local filename, content = mcp.get_current_buffer()

  local prompt = ""
  if selection and selection ~= "" then
    prompt = string.format("Refactor the following selected code from `%s`:\n\n```%s\n%s\n```", filename, vim.bo.filetype, selection)
  else
    prompt = string.format("Refactor the code in the current buffer `%s`:\n\n```%s\n%s\n```", filename, vim.bo.filetype, content)
  end

  execute_prompt(prompt)
end

--- `:KiroFix` command handler
function M.fix()
  local filename, content = mcp.get_current_buffer()
  local diagnostics = mcp.get_diagnostics()

  if diagnostics == "" then
    vim.notify("[Kiro] No LSP diagnostics compiler/linter errors found to fix in this buffer.", vim.log.levels.INFO)
    return
  end

  local prompt = string.format(
    "Please fix the compilation/LSP diagnostic issues in the buffer `%s`.\n\nCode:\n```%s\n%s\n```\n\nIssues:\n%s",
    filename,
    vim.bo.filetype,
    content,
    diagnostics
  )

  execute_prompt(prompt)
end

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

  cmd("KiroChat", function() chat.toggle() end, {})
  cmd("Kiro", function() chat.toggle() end, {})

  cmd("KiroExplain", function() M.explain() end, { range = true })
  cmd("KiroRefactor", function() M.refactor() end, { range = true })
  cmd("KiroFix", function() M.fix() end, {})

  cmd("KiroApprove", function() M.handle_pending_approval(true) end, {})
  cmd("KiroReject", function() M.handle_pending_approval(false) end, {})
end

return M
