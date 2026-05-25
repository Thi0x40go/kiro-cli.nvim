local config = require("kiro.config")
local diff_viewer = require("kiro.ui.diff")

local M = {}

--- Helper to open a floating window centered on the screen
--- @param width number
--- @param height number
--- @param title string
--- @return number bufnr, number winid
local function open_float(width, height, title)
  local screen_w = vim.o.columns
  local screen_h = vim.o.lines

  local row = math.floor((screen_h - height) / 2)
  local col = math.floor((screen_w - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  
  local opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  }

  local win = vim.api.nvim_open_win(buf, true, opts)
  return buf, win
end

--- Show the tool approval window
--- @param opts { tool_name: string, tool_input: table, risk_level: "Low"|"Medium"|"High", reason: string, cwd: string, on_choice: fun(approved: boolean) }
function M.show(opts)
  local tool_name = opts.tool_name
  local tool_input = opts.tool_input
  local risk_level = opts.risk_level
  local reason = opts.reason
  local on_choice = opts.on_choice

  local width = 65
  local height = 11
  
  local buf, win = open_float(width, height, "Kiro Tool Approval Gate")

  -- Build lines
  local file_or_cmd = ""
  local is_file_op = false
  local file_path = ""
  local new_content = ""

  if tool_name == "bash" or tool_name == "execute_bash" or tool_name == "shell" or tool_name == "run_command" then
    file_or_cmd = tool_input.command or tool_input.cmd or ""
  elseif tool_name == "write" or tool_name == "fs_write" or tool_name == "edit" then
    is_file_op = true
    file_path = tool_input.path or tool_input.filepath or ""
    new_content = tool_input.content or tool_input.text or ""
    file_or_cmd = vim.fn.fnamemodify(file_path, ":~:.")
  elseif tool_name == "delete" or tool_name == "fs_delete" or tool_name == "rm" then
    file_path = tool_input.path or tool_input.filepath or ""
    file_or_cmd = vim.fn.fnamemodify(file_path, ":~:.")
  else
    -- Generic arguments dump
    file_or_cmd = vim.json.encode(tool_input)
  end

  -- Truncate command display if too long
  if #file_or_cmd > 50 then
    file_or_cmd = file_or_cmd:sub(1, 47) .. "..."
  end

  local lines = {
    "",
    "  Tool:       " .. tool_name,
    "  Target:     " .. file_or_cmd,
    "  Risk Level: " .. risk_level:upper() .. " (" .. reason .. ")",
    "",
    "  ─────────────────────────────────────────────────────────",
    "   [a] Approve tool execution       [d] Deny / Block tool",
  }

  if is_file_op then
    table.insert(lines, "   [v] View proposed changes diff")
  else
    table.insert(lines, "")
  end
  table.insert(lines, "   [q] Close & Deny")

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Add highlights
  local ns_id = vim.api.nvim_create_namespace("kiro_approval")
  
  -- Highlights for labels
  vim.api.nvim_buf_add_highlight(buf, ns_id, "Title", 1, 2, 13)
  vim.api.nvim_buf_add_highlight(buf, ns_id, "Directory", 2, 2, 13)
  vim.api.nvim_buf_add_highlight(buf, ns_id, "Title", 3, 2, 13)

  -- Highlight risk levels
  local risk_hl = "DiagnosticInfo"
  if risk_level == "Low" then
    risk_hl = "DiagnosticOk"
  elseif risk_level == "Medium" then
    risk_hl = "DiagnosticWarn"
  elseif risk_level == "High" then
    risk_hl = "DiagnosticError"
  end
  vim.api.nvim_buf_add_highlight(buf, ns_id, risk_hl, 3, 14, 14 + #risk_level)

  -- Highlights for keyboard shortcut actions
  vim.api.nvim_buf_add_highlight(buf, ns_id, "DiagnosticOk", 6, 3, 6)
  vim.api.nvim_buf_add_highlight(buf, ns_id, "DiagnosticError", 6, 36, 39)
  if is_file_op then
    vim.api.nvim_buf_add_highlight(buf, ns_id, "DiagnosticInfo", 7, 3, 6)
  end

  -- Set buffer options
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

  local diff_win = nil
  local diff_buf = nil
  local side_by_side_wins = nil

  local choice_made = false

  -- Helper function to close all UI windows associated with this approval
  local function cleanup()
    if choice_made then return end
    choice_made = true

    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if diff_win and vim.api.nvim_win_is_valid(diff_win) then
      vim.api.nvim_win_close(diff_win, true)
    end
    if side_by_side_wins then
      for _, w in ipairs(side_by_side_wins) do
        if vim.api.nvim_win_is_valid(w) then
          vim.api.nvim_win_close(w, true)
        end
      end
    end
  end

  -- Handle decision
  local function make_choice(approved)
    cleanup()
    pcall(function()
      require("kiro").pending_approval_callback = nil
    end)
    if on_choice then
      on_choice(approved)
    end
  end

  pcall(function()
    require("kiro").pending_approval_callback = make_choice
  end)

  -- Handle window closed unexpectedly (fallback deny)
  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = buf,
    callback = function()
      if not choice_made then
        make_choice(false)
      end
    end,
    once = true,
  })

  -- Keybindings helper
  local function bind(key, cb)
    vim.keymap.set("n", key, cb, { buffer = buf, silent = true, nowait = true })
  end

  bind(config.values.keymaps.approve, function() make_choice(true) end)
  bind(config.values.keymaps.deny, function() make_choice(false) end)
  bind(config.values.keymaps.close, function() make_choice(false) end)

  -- Toggle diff view
  if is_file_op then
    bind(config.values.keymaps.view_diff, function()
      if config.values.diff_preview_mode == "side-by-side" then
        -- Open side-by-side diff
        cleanup()
        local win_orig, win_new, buf_orig, buf_new = diff_viewer.render_side_by_side(
          vim.api.nvim_get_current_win(),
          file_path,
          new_content
        )
        side_by_side_wins = { win_orig, win_new }

        -- Setup local binds in the side-by-side windows too
        local function bind_diff(b)
          vim.keymap.set("n", config.values.keymaps.approve, function() make_choice(true) end, { buffer = b, silent = true })
          vim.keymap.set("n", config.values.keymaps.deny, function() make_choice(false) end, { buffer = b, silent = true })
          vim.keymap.set("n", config.values.keymaps.close, function() make_choice(false) end, { buffer = b, silent = true })
        end
        bind_diff(buf_orig)
        bind_diff(buf_new)
      else
        -- Toggle floating unified diff
        if diff_win and vim.api.nvim_win_is_valid(diff_win) then
          vim.api.nvim_win_close(diff_win, true)
          diff_win = nil
        else
          local diff_w = 80
          local diff_h = 15
          diff_buf, diff_win = open_float(diff_w, diff_h, "Proposed File Changes Diff")
          diff_viewer.render_unified(diff_buf, file_path, new_content)
          
          -- Bind keys inside diff window to approve/deny too
          vim.keymap.set("n", config.values.keymaps.approve, function() make_choice(true) end, { buffer = diff_buf, silent = true })
          vim.keymap.set("n", config.values.keymaps.deny, function() make_choice(false) end, { buffer = diff_buf, silent = true })
          vim.keymap.set("n", config.values.keymaps.close, function()
            vim.api.nvim_win_close(diff_win, true)
            diff_win = nil
          end, { buffer = diff_buf, silent = true })
        end
      end
    end)
  end
end

return M
