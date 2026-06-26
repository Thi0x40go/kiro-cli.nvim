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

--- Play an alert sound when the approval modal appears, if enabled
local function play_sound()
  if not config.values.enable_sound then
    return
  end

  local function try_cmd(cmd)
    if vim.fn.executable(cmd[1]) == 1 then
      vim.fn.jobstart(cmd)
      return true
    end
    return false
  end

  if vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1 then
    try_cmd({ "afplay", "/System/Library/Sounds/Ping.aiff" })
  elseif vim.fn.has("win32") == 1 then
    if not try_cmd({ "powershell.exe", "-c", "[System.Media.SystemSounds]::Beep.Play()" }) then
      io.write("\a")
    end
  else
    -- Linux / Unix fallback
    if not try_cmd({ "canberra-gtk-play", "-i", "bell" }) then
      if not try_cmd({ "pw-play", "/usr/share/sounds/freedesktop/stereo/bell.oga" }) then
        if not try_cmd({ "paplay", "/usr/share/sounds/freedesktop/stereo/bell.oga" }) then
          if not try_cmd({ "aplay", "/usr/share/sounds/alsa/Front_Center.wav" }) then
            io.write("\a")
          end
        end
      end
    end
  end
end

--- Show the tool approval window
--- @param opts { tool_name: string, tool_input: table, risk_level: "Low"|"Medium"|"High", reason: string, cwd: string, on_choice: fun(approved: boolean), is_reopen?: boolean }
function M.show(opts)
  if not opts.is_reopen then
    play_sound()
  end

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
    local raw_content = tool_input.content or tool_input.text or ""

    -- Read original content of the file
    local original_content = ""
    if file_path ~= "" then
      local f = io.open(file_path, "r")
      if f then
        original_content = f:read("*a")
        f:close()
      end
    end

    -- Construct new_content based on the write command type
    local command = tool_input.command or ""
    if command == "strReplace" then
      local old_str = tool_input.oldStr or ""
      local new_str = tool_input.newStr or ""
      if old_str ~= "" then
        local start_idx, end_idx = original_content:find(old_str, 1, true)
        if start_idx then
          new_content = original_content:sub(1, start_idx - 1) .. new_str .. original_content:sub(end_idx + 1)
        else
          new_content = original_content
        end
      else
        new_content = original_content
      end
    elseif command == "insert" or command == "append" then
      new_content = original_content .. raw_content
    else
      new_content = raw_content
    end

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
  local created_buffers = { buf }

  local choice_made = false
  local switching_to_diff = false

  -- Helper function to close all UI windows associated with this approval
  local function cleanup()
    if choice_made then return end
    if not switching_to_diff then
      choice_made = true
    end

    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if diff_win and vim.api.nvim_win_is_valid(diff_win) then
      vim.api.nvim_win_close(diff_win, true)
    end
    if side_by_side_wins then
      for _, w in ipairs(side_by_side_wins) do
        if vim.api.nvim_win_is_valid(w) then
          pcall(vim.api.nvim_win_close, w, true)
        end
      end
    end

    -- Clean up all created buffers on final decision
    if not switching_to_diff then
      for _, b in ipairs(created_buffers) do
        if vim.api.nvim_buf_is_valid(b) then
          pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
      end
      created_buffers = {}
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
      if not choice_made and not switching_to_diff then
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
        switching_to_diff = true
        cleanup()
        local win_orig, win_new, buf_orig, buf_new = diff_viewer.render_side_by_side(
          vim.api.nvim_get_current_win(),
          file_path,
          new_content
        )
        side_by_side_wins = { win_orig, win_new }
        table.insert(created_buffers, buf_orig)
        table.insert(created_buffers, buf_new)

        local side_by_side_closed = false
        local function close_diff_and_reopen()
          if side_by_side_closed then return end
          side_by_side_closed = true

          -- Close side-by-side windows
          if side_by_side_wins then
            for _, w in ipairs(side_by_side_wins) do
              if vim.api.nvim_win_is_valid(w) then
                pcall(vim.api.nvim_win_close, w, true)
              end
            end
            side_by_side_wins = nil
          end

          -- Delete side-by-side buffers immediately to prevent E95 name collision
          if buf_orig and vim.api.nvim_buf_is_valid(buf_orig) then
            pcall(vim.api.nvim_buf_delete, buf_orig, { force = true })
          end
          if buf_new and vim.api.nvim_buf_is_valid(buf_new) then
            pcall(vim.api.nvim_buf_delete, buf_new, { force = true })
          end

          -- Remove from created_buffers tracking list
          local new_created = {}
          for _, b in ipairs(created_buffers) do
            if b ~= buf_orig and b ~= buf_new then
              table.insert(new_created, b)
            end
          end
          created_buffers = new_created

          -- Re-open approval popup
          local new_opts = vim.tbl_extend("force", opts, { is_reopen = true })
          M.show(new_opts)
        end

        -- Setup local binds in the side-by-side windows
        local function bind_diff(b)
          vim.keymap.set("n", config.values.keymaps.close, close_diff_and_reopen, { buffer = b, silent = true })
          vim.keymap.set("n", config.values.keymaps.view_diff, close_diff_and_reopen, { buffer = b, silent = true })
        end
        bind_diff(buf_orig)
        bind_diff(buf_new)

        -- Handle split window closed or buffer exited unexpectedly
        vim.api.nvim_create_autocmd("BufWinLeave", {
          buffer = buf_orig,
          callback = close_diff_and_reopen,
          once = true,
        })
        vim.api.nvim_create_autocmd("BufWinLeave", {
          buffer = buf_new,
          callback = close_diff_and_reopen,
          once = true,
        })
      else
        -- Toggle floating unified diff
        if diff_win and vim.api.nvim_win_is_valid(diff_win) then
          local w = diff_win
          local b = diff_buf
          diff_win = nil
          diff_buf = nil
          if w and vim.api.nvim_win_is_valid(w) then
            vim.api.nvim_win_close(w, true)
          end
          vim.schedule(function()
            if b and vim.api.nvim_buf_is_valid(b) then
              pcall(vim.api.nvim_buf_delete, b, { force = true })
            end
          end)
        else
          local diff_w = 80
          local diff_h = 15
          diff_buf, diff_win = open_float(diff_w, diff_h, "Proposed File Changes Diff")
          diff_viewer.render_unified(diff_buf, file_path, new_content)
          diff_viewer.apply_winhighlight(diff_win)
          table.insert(created_buffers, diff_buf)
          vim.cmd("stopinsert")
          
          local function close_unified_diff()
            local w = diff_win
            local b = diff_buf
            diff_win = nil
            diff_buf = nil
            if w and vim.api.nvim_win_is_valid(w) then
              vim.api.nvim_win_close(w, true)
            end
            vim.schedule(function()
              if b and vim.api.nvim_buf_is_valid(b) then
                pcall(vim.api.nvim_buf_delete, b, { force = true })
              end
            end)
          end

          -- Bind keys inside diff window to close/toggle
          vim.keymap.set("n", config.values.keymaps.close, close_unified_diff, { buffer = diff_buf, silent = true })
          vim.keymap.set("n", config.values.keymaps.view_diff, close_unified_diff, { buffer = diff_buf, silent = true })
        end
      end
    end)
  end
end

return M
