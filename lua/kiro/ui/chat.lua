local config = require("kiro.config")

local M = {}

local out_buf = nil
local out_win = nil
local in_buf = nil
local in_win = nil

local is_streaming = false
local current_assistant_lines = 0

--- Create split windows for chat
--- @return number out_b, number out_w, number in_b, number in_w
local function create_split_layout()
  -- Open a vertical split on the far right
  vim.cmd("botright vsplit")
  out_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(out_win, 50)
  out_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(out_win, out_buf)

  -- Create input split at the bottom
  vim.cmd("split")
  in_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(in_win, 4)
  in_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(in_win, in_buf)

  return out_buf, out_win, in_buf, in_win
end

--- Create floating windows for chat
--- @return number out_b, number out_w, number in_b, number in_w
local function create_float_layout()
  local screen_w = vim.o.columns
  local screen_h = vim.o.lines

  local width = 90
  local out_height = 20
  local in_height = 3

  local total_h = out_height + in_height + 4
  local start_row = math.floor((screen_h - total_h) / 2)
  local start_col = math.floor((screen_w - width) / 2)

  -- Create Output Float
  out_buf = vim.api.nvim_create_buf(false, true)
  local out_opts = {
    relative = "editor",
    width = width,
    height = out_height,
    row = start_row,
    col = start_col,
    style = "minimal",
    border = "rounded",
    title = " Kiro Assistant Output ",
    title_pos = "center",
  }
  out_win = vim.api.nvim_open_win(out_buf, false, out_opts)

  -- Create Input Float directly below
  in_buf = vim.api.nvim_create_buf(false, true)
  local in_opts = {
    relative = "editor",
    width = width,
    height = in_height,
    row = start_row + out_height + 2,
    col = start_col,
    style = "minimal",
    border = "rounded",
    title = " Prompt Input ",
    title_pos = "center",
  }
  in_win = vim.api.nvim_open_win(in_buf, true, in_opts)

  return out_buf, out_win, in_buf, in_win
end

--- Setup visual appearance and options for windows
local function configure_options()
  -- Output buffer configurations
  vim.api.nvim_set_option_value("modifiable", false, { buf = out_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = out_buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = out_buf })
  vim.api.nvim_set_option_value("wrap", true, { win = out_win })

  -- Input buffer configurations
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = in_buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = in_buf })
  vim.api.nvim_set_option_value("wrap", true, { win = in_win })

  -- Set buffer initial text
  vim.api.nvim_set_option_value("modifiable", true, { buf = out_buf })
  vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, {
    " Welcome to Kiro ACP Mode! Type your request below and press <CR>.",
    " ─────────────────────────────────────────────────────────────────",
    "",
  })
  vim.api.nvim_set_option_value("modifiable", false, { buf = out_buf })
end

--- Close both chat windows
function M.close()
  if out_win and vim.api.nvim_win_is_valid(out_win) then
    vim.api.nvim_win_close(out_win, true)
  end
  if in_win and vim.api.nvim_win_is_valid(in_win) then
    vim.api.nvim_win_close(in_win, true)
  end
  out_win = nil
  in_win = nil
  out_buf = nil
  in_buf = nil
end

--- Append content to output window
--- @param text string
--- @param hl_group? string
function M.append_text(text, hl_group)
  if not out_buf or not vim.api.nvim_buf_is_valid(out_buf) then return end

  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_set_option_value("modifiable", true, { buf = out_buf })
  
  local last_idx = vim.api.nvim_buf_line_count(out_buf)
  vim.api.nvim_buf_set_lines(out_buf, -1, -1, false, lines)
  
  if hl_group then
    local ns = vim.api.nvim_create_namespace("kiro_chat_hl")
    for i = 0, #lines - 1 do
      vim.api.nvim_buf_add_highlight(out_buf, ns, hl_group, last_idx + i, 0, -1)
    end
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = out_buf })
  M.scroll_to_bottom()
end

--- Append streaming token to output window
--- @param token string
function M.append_token(token)
  if not out_buf or not vim.api.nvim_buf_is_valid(out_buf) then return end

  local last_line_idx = vim.api.nvim_buf_line_count(out_buf) - 1
  local last_line = vim.api.nvim_buf_get_lines(out_buf, last_line_idx, last_line_idx + 1, false)[1] or ""

  local parts = vim.split(token, "\n", { plain = true })
  local lines_to_set = { last_line .. parts[1] }
  for i = 2, #parts do
    table.insert(lines_to_set, parts[i])
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = out_buf })
  vim.api.nvim_buf_set_lines(out_buf, last_line_idx, -1, false, lines_to_set)
  vim.api.nvim_set_option_value("modifiable", false, { buf = out_buf })

  M.scroll_to_bottom()
end

--- Scroll output window to bottom
function M.scroll_to_bottom()
  if out_win and vim.api.nvim_win_is_valid(out_win) then
    local count = vim.api.nvim_buf_line_count(out_buf)
    vim.api.nvim_win_set_cursor(out_win, { count, 0 })
  end
end

--- Yank conversation history to system clipboard
function M.yank_history()
  if not out_buf or not vim.api.nvim_buf_is_valid(out_buf) then return end
  local lines = vim.api.nvim_buf_get_lines(out_buf, 0, -1, false)
  local content = table.concat(lines, "\n")
  vim.fn.setreg("+", content)
  vim.notify("[Kiro] Conversation history yanked to clipboard.", vim.log.levels.INFO)
end

--- Open and build layout for the chat session
function M.toggle()
  if out_win and vim.api.nvim_win_is_valid(out_win) then
    M.close()
    return
  end

  if config.values.position == "split" then
    create_split_layout()
  else
    create_float_layout()
  end

  configure_options()

  -- Register keymaps
  local function bind(b, key, cb)
    vim.keymap.set("n", key, cb, { buffer = b, silent = true, nowait = true })
  end

  bind(out_buf, config.values.keymaps.close, M.close)
  bind(in_buf, config.values.keymaps.close, M.close)
  
  bind(out_buf, config.values.keymaps.yank, M.yank_history)
  bind(in_buf, config.values.keymaps.yank, M.yank_history)

  -- Send prompt keymap (inserts input from user)
  vim.keymap.set("i", config.values.keymaps.send_prompt, function()
    M.submit_prompt()
  end, { buffer = in_buf, silent = true })

  vim.keymap.set("n", config.values.keymaps.send_prompt, function()
    M.submit_prompt()
  end, { buffer = in_buf, silent = true })
end

--- Submit the input prompt to the Kiro client
function M.submit_prompt()
  if is_streaming then
    vim.notify("[Kiro] Busy processing a prompt. Please wait or cancel.", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(in_buf, 0, -1, false)
  local prompt_text = table.concat(lines, "\n")
  prompt_text = vim.trim(prompt_text)

  if prompt_text == "" then return end

  -- Clear input buffer
  vim.api.nvim_buf_set_lines(in_buf, 0, -1, false, {})

  -- Append request to output window
  M.append_text("\n\n❯ You:", "Title")
  M.append_text(prompt_text)
  M.append_text("\n❯ Kiro Assistant:", "Comment")
  M.append_text("") -- Prepare empty line for streaming

  is_streaming = true

  -- Access the client from main module
  local kiro = require("kiro")
  if not kiro.client or not kiro.client.is_running then
    kiro.start_client()
  end

  -- Context / MCP integrations (Gather LSP diagnostics and add to message context if enabled)
  local context_payload = prompt_text
  if config.values.mcp_enabled then
    local mcp = require("kiro.mcp")
    local context_info = mcp.get_context()
    if context_info ~= "" then
      context_payload = context_payload .. "\n\n[Editor Context Contextual Data]\n" .. context_info
    end
  end

  kiro.client:prompt(context_payload, function(result, err)
    is_streaming = false
    if err then
      M.append_text("\n[Error] Prompt failed: " .. vim.inspect(err), "DiagnosticError")
    end
  end)
end

--- Handle events forwarded by client
--- @param event_type string
--- @param data table
function M.handle_client_event(event_type, data)
  if event_type == "notification" then
    local utype = data.type
    local udata = data.data

    if utype == "AgentMessageChunk" or utype == "agent_message_chunk" then
      local chunk = udata.content or udata.chunk or udata.text or ""
      vim.schedule(function()
        M.append_token(chunk)
      end)
    elseif utype == "ToolCall" or utype == "tool_call" then
      local tool_name = udata.name or udata.tool or "unknown"
      local t_input = udata.arguments or udata.tool_input or {}
      local arg_str = vim.json.encode(t_input)
      if #arg_str > 40 then arg_str = arg_str:sub(1, 37) .. "..." end
      
      vim.schedule(function()
        M.append_text("\n🔧 [Kiro Invoking Tool: " .. tool_name .. " with arguments " .. arg_str .. "]", "DiagnosticWarn")
      end)
    elseif utype == "TurnEnd" or utype == "turn_end" then
      is_streaming = false
      vim.schedule(function()
        M.append_text("\n─────────────────────────────────────────────────────────────────")
      end)
    end
  elseif event_type == "exit" then
    is_streaming = false
    vim.schedule(function()
      M.append_text("\n🛑 [Kiro Client process exited. Exit Code: " .. tostring(data.code) .. "]", "DiagnosticError")
    end)
  elseif event_type == "stderr" then
    -- Log internal stderr updates for transparency
    local log = data.content or ""
    if log:match("error") or log:match("failed") then
      vim.schedule(function()
        M.append_text("\n⚠️ [Kiro Dev stderr] " .. log, "Comment")
      end)
    end
  end
end

return M
