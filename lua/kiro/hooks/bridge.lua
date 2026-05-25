local config = require("kiro.config")

local M = {}

local server_handle = nil
local active_connections = {}

local function log_server(msg)
  local f = io.open("/tmp/kiro_bridge_server.log", "a")
  if f then
    f:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), msg))
    f:close()
  end
end

--- Check if the socket path is a TCP address (contains host:port)
--- @param path string
--- @return boolean
local function is_tcp_address(path)
  return path:match("^[%d%.]+:%d+$") ~= nil or path:match("^localhost:%d+$") ~= nil
end

--- Parse TCP host and port
--- @param path string
--- @return string host, number port
local function parse_tcp(path)
  local host, port = path:match("^([^:]+):(%d+)$")
  if not host then
    host = "127.0.0.1"
    port = 49999
  end
  return host, tonumber(port)
end

--- Detect if a tool execution is destructive or violates security guidelines
--- @param tool_name string
--- @param tool_input table
--- @return boolean is_danger, string reason
local function check_security_risk(tool_name, tool_input)
  -- 1. Check for shell execution tools
  if tool_name == "bash" or tool_name == "execute_bash" or tool_name == "shell" or tool_name == "run_command" then
    local cmd = tool_input.command or tool_input.cmd or ""
    cmd = cmd:lower()

    if cmd:match("rm%s+%-rf") or cmd:match("rm%s+%-r") then
      return true, "Destructive command (rm -rf)"
    end
    if cmd:match("chmod") or cmd:match("chown") then
      return true, "System permissions modification"
    end
    if cmd:match("ssh%-key") or cmd:match("%.ssh") or cmd:match("ssh%-add") then
      return true, "SSH keys or agent access attempt"
    end
    if cmd:match("%.env") or cmd:match("passwd") or cmd:match("shadow") or cmd:match("secret") or cmd:match("token") then
      return true, "Sensitive credential file access"
    end
    if cmd:match("curl%s+.*|") or cmd:match("wget%s+.*|") or cmd:match("bash%s+%-c") then
      return true, "Remote code execution vector"
    end
  end

  -- 2. Check for file deletion
  if tool_name == "delete" or tool_name == "fs_delete" or tool_name == "rm" then
    local path = tool_input.path or tool_input.filepath or ""
    if path:match("%.env") or path:match("%.git") or path:match("config") then
      return true, "Sensitive file deletion"
    end
  end

  -- 3. Check for file writes to credentials/sensitive areas
  if tool_name == "write" or tool_name == "fs_write" or tool_name == "edit" then
    local path = tool_input.path or tool_input.filepath or ""
    if path:match("%.ssh/") or path:match("%.env") then
      return true, "Sensitive file modification"
    end
  end

  return false, ""
end

--- Determine if a tool should be auto-approved based on config and security risk
--- @param tool_name string
--- @param tool_input table
--- @return boolean auto_approve, string risk_level, string risk_reason
function M.evaluate_tool(tool_name, tool_input)
  local is_danger, danger_reason = check_security_risk(tool_name, tool_input)
  if is_danger then
    return false, "High", danger_reason
  end

  -- Determine if tool is read-only / safe
  local is_safe = false
  for _, allowed in ipairs(config.values.allowed_tools or {}) do
    if allowed == tool_name then
      is_safe = true
      break
    end
  end

  if is_safe and config.values.auto_approve_safe_tools then
    return true, "Low", "Safe tool auto-approved"
  end

  return false, "Medium", "Requires user verification"
end

--- Start the bridge socket server in Neovim
function M.start()
  if server_handle then return end

  local path = config.values.hook_socket_path
  local is_tcp = is_tcp_address(path)

  local server
  if is_tcp then
    local host, port = parse_tcp(path)
    server = vim.loop.new_tcp()
    local bind_ok, bind_err = server:bind(host, port)
    if not bind_ok then
      vim.notify("[Kiro Bridge] TCP Bind failed on " .. host .. ":" .. port .. ": " .. tostring(bind_err), vim.log.levels.ERROR)
      return
    end
  else
    -- Clean up stale socket path if on Unix
    vim.fn.delete(path)
    server = vim.loop.new_pipe(false)
    local bind_ok, bind_err = server:bind(path)
    if not bind_ok then
      vim.notify("[Kiro Bridge] Pipe Bind failed on " .. path .. ": " .. tostring(bind_err), vim.log.levels.ERROR)
      return
    end
  end

  local listen_ok, listen_err = server:listen(128, function(err)
    if err then
      log_server("Socket listen callback error: " .. tostring(err))
      vim.notify("[Kiro Bridge] Socket listen error: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    local connection
    if is_tcp then
      connection = vim.loop.new_tcp()
    else
      connection = vim.loop.new_pipe(false)
    end

    server:accept(connection)
    log_server("Accepted new connection client!")
    table.insert(active_connections, connection)

    local buffer = ""
    connection:read_start(function(read_err, chunk)
      if read_err then
        log_server("Connection read error: " .. tostring(read_err))
        connection:close()
        return
      end

      if chunk then
        log_server("Received chunk of length " .. #chunk .. ": " .. chunk)
        buffer = buffer .. chunk
        if buffer:sub(-1) == "\n" or buffer:find("\n") then
          log_server("Detected newline delimiter, attempting JSON decode...")
          local ok, payload = pcall(vim.json.decode, buffer)
          if ok and payload then
            log_server("JSON decode successful! Processing hook request...")
            buffer = ""
            vim.schedule(function()
              M.process_hook_request(connection, payload)
            end)
          else
            log_server("JSON decode failed: " .. tostring(payload))
          end
        end
      else
        log_server("Connection closed by client EOF")
        connection:close()
      end
    end)
  end)

  if not listen_ok then
    vim.notify("[Kiro Bridge] Failed to listen: " .. tostring(listen_err), vim.log.levels.ERROR)
    return
  end

  server_handle = server
end

--- Process the incoming hook request payload and respond
--- @param connection userdata vim.loop stream
--- @param payload table
function M.process_hook_request(connection, payload)
  local tool_name = payload.tool_name or payload.tool or "unknown"
  local tool_input = payload.tool_input or payload.arguments or {}

  local auto_approve, risk_level, reason = M.evaluate_tool(tool_name, tool_input)

  local function send_decision(approved)
    local response = vim.json.encode({ approved = approved }) .. "\n"
    if not connection:is_closing() then
      connection:write(response, function()
        connection:close()
      end)
    end
  end

  if auto_approve then
    send_decision(true)
    return
  end

  -- Not auto-approved: trigger visual popup in Neovim
  local approval_ui = require("kiro.ui.approval")
  approval_ui.show({
    tool_name = tool_name,
    tool_input = tool_input,
    risk_level = risk_level,
    reason = reason,
    cwd = payload.cwd,
    on_choice = function(approved)
      send_decision(approved)
    end,
  })
end

--- Stop the bridge server and close connections
function M.stop()
  for _, conn in ipairs(active_connections) do
    if not conn:is_closing() then
      conn:close()
    end
  end
  active_connections = {}

  if server_handle then
    server_handle:close()
    server_handle = nil
  end

  local path = config.values.hook_socket_path
  if not is_tcp_address(path) then
    vim.fn.delete(path)
  end
end

return M
