local rpc_mod = require("kiro.acp.rpc")
local config = require("kiro.config")

local M = {}

--- @class KiroClient
--- @field handle userdata|nil vim.loop process handle
--- @field stdin userdata|nil vim.loop pipe for stdin
--- @field stdout userdata|nil vim.loop pipe for stdout
--- @field stderr userdata|nil vim.loop pipe for stderr
--- @field rpc_parser KiroRPC|nil JSON-RPC parser
--- @field req_id number message counter
--- @field callbacks table<number, fun(result: table|nil, err: table|nil)> pending request callbacks
--- @field session_id string|nil current active session UUID
--- @field agent_capabilities table capabilities returned by Kiro agent
--- @field on_event fun(event_type: string, data: table)|nil callback to notify UI or commands
--- @field is_running boolean status of process
local Client = {}
Client.__index = Client

local SESSION_FILE = vim.fn.stdpath("cache") .. "/kiro_session_id.txt"

--- Save session ID to cache
--- @param session_id string
local function save_session(session_id)
  if not config.values.session_persistence then return end
  local f = io.open(SESSION_FILE, "w")
  if f then
    f:write(session_id)
    f:close()
  end
end

--- Load persisted session ID from cache
--- @return string|nil
local function load_session()
  if not config.values.session_persistence then return nil end
  local f = io.open(SESSION_FILE, "r")
  if f then
    local id = f:read("*a")
    f:close()
    id = vim.trim(id)
    if id ~= "" then return id end
  end
  return nil
end

--- Create a new client instance
--- @param on_event fun(event_type: string, data: table)
--- @return KiroClient
function Client.new(on_event)
  local self = setmetatable({}, Client)
  self.req_id = 0
  self.callbacks = {}
  self.is_running = false
  self.on_event = on_event
  self.agent_capabilities = {}
  return self
end

--- Start the kiro-cli acp process
function Client:start()
  if self.is_running then return end

  self.stdin = vim.loop.new_pipe(false)
  self.stdout = vim.loop.new_pipe(false)
  self.stderr = vim.loop.new_pipe(false)

  local args = { "acp" }

  -- Spawn the process
  local kiro_cmd = config.values.kiro_cmd or "kiro-cli"
  local spawn_opts = {
    args = args,
    stdio = { self.stdin, self.stdout, self.stderr },
    cwd = vim.fn.getcwd(),
  }

  local handle, pid
  handle, pid = vim.loop.spawn(kiro_cmd, spawn_opts, function(code, signal)
    self.is_running = false
    if self.handle then
      self.handle:close()
      self.handle = nil
    end
    if self.on_event then
      self.on_event("exit", { code = code, signal = signal })
    end
  end)

  if not handle then
    vim.notify("[Kiro] Failed to spawn Kiro CLI process. Ensure '" .. kiro_cmd .. "' is installed and in your PATH.", vim.log.levels.ERROR)
    return false
  end

  self.handle = handle
  self.is_running = true

  -- Initialize JSON-RPC Parser
  self.rpc_parser = rpc_mod.RPC.new({
    on_notification = function(method, params)
      self:handle_notification(method, params)
    end,
    on_request = function(id, method, params)
      self:handle_request(id, method, params)
    end,
    on_response = function(id, result, err)
      local cb = self.callbacks[id]
      if cb then
        self.callbacks[id] = nil
        cb(result, err)
      end
    end,
  })

  -- Read stdout
  self.stdout:read_start(function(err, data)
    if err then
      vim.notify("[Kiro] Stdout read error: " .. tostring(err), vim.log.levels.ERROR)
      return
    end
    if data then
      self.rpc_parser:feed(data)
    end
  end)

  -- Read stderr (useful for debugging)
  self.stderr:read_start(function(err, data)
    if err then return end
    if data and data ~= "" then
      if self.on_event then
        self.on_event("stderr", { content = data })
      end
    end
  end)

  -- Trigger Handshake
  self:initialize()

  return true
end

--- Send a request to Kiro CLI
--- @param method string
--- @param params table
--- @param callback fun(result: table|nil, err: table|nil)
function Client:request(method, params, callback)
  if not self.is_running then
    vim.notify("[Kiro] Cannot send request: process not running.", vim.log.levels.WARN)
    return
  end
  self.req_id = self.req_id + 1
  local id = self.req_id
  self.callbacks[id] = callback

  local payload = rpc_mod.format_request(id, method, params)
  self.stdin:write(payload)
end

--- Send a notification to Kiro CLI
--- @param method string
--- @param params table
function Client:notify(method, params)
  if not self.is_running then return end
  local payload = rpc_mod.format_notification(method, params)
  self.stdin:write(payload)
end

--- Handshake initialize method
function Client:initialize()
  local params = {
    protocolVersion = 1,
    clientCapabilities = {
      fs = {
        readTextFile = true,
        writeTextFile = true,
      },
      terminal = true,
    },
    clientInfo = {
      name = "kiro-cli.nvim",
      version = "1.0.0",
    },
  }

  self:request("initialize", params, function(result, err)
    if err then
      vim.notify("[Kiro] Initialization failed: " .. vim.inspect(err), vim.log.levels.ERROR)
      return
    end

    self.agent_capabilities = result.agentCapabilities or {}

    -- Proceed to new/load session
    self:setup_session()
  end)
end

--- Load or create session
function Client:setup_session()
  local persisted_id = load_session()

  if persisted_id and self.agent_capabilities.loadSession then
    -- Try to load session
    self:request("session/load", { sessionId = persisted_id }, function(result, err)
      if err then
        -- Persistent session not found or expired; start a new one
        self:create_new_session()
      else
        self.session_id = persisted_id
        if self.on_event then
          self.on_event("session_ready", { session_id = self.session_id, loaded = true })
        end
      end
    end)
  else
    self:create_new_session()
  end
end

--- Create a new session
function Client:create_new_session()
  local params = {
    cwd = vim.fn.getcwd(),
  }

  self:request("session/new", params, function(result, err)
    if err then
      vim.notify("[Kiro] Failed to create session: " .. vim.inspect(err), vim.log.levels.ERROR)
      return
    end

    self.session_id = result.sessionId
    if self.session_id then
      save_session(self.session_id)
      if self.on_event then
        self.on_event("session_ready", { session_id = self.session_id, loaded = false })
      end
    end
  end)
end

--- Send prompt user request
--- @param text string
--- @param callback fun(result: table|nil, err: table|nil)
function Client:prompt(text, callback)
  if not self.session_id then
    vim.notify("[Kiro] Session not ready.", vim.log.levels.WARN)
    return
  end

  local params = {
    sessionId = self.session_id,
    prompt = text,
  }

  self:request("session/prompt", params, callback)
end

--- Cancel ongoing session prompt
function Client:cancel()
  if not self.session_id then return end
  self:notify("session/cancel", { sessionId = self.session_id })
end

--- Close connection and stop process
function Client:close()
  if not self.is_running then return end
  self.is_running = false

  if self.stdin then self.stdin:close() end
  if self.stdout then self.stdout:close() end
  if self.stderr then self.stderr:close() end

  if self.handle then
    self.handle:kill(15) -- SIGTERM
    self.handle:close()
    self.handle = nil
  end
end

--- Helper to safely parse ACP SessionUpdate variant payload
--- @param update table
--- @return string|nil type, table|nil data
local function parse_update(update)
  if not update then return nil, nil end
  if type(update) == "string" then
    return update, {}
  end
  if type(update) ~= "table" then return nil, nil end
  if update.type then
    return update.type, update
  end
  for k, v in pairs(update) do
    if k ~= "_meta" then
      if type(v) == "table" then
        return k, v
      elseif v == true or type(v) == "string" then
        return k, {}
      end
    end
  end
  return nil, nil
end

--- Handle server-to-client notifications
--- @param method string
--- @param params table
function Client:handle_notification(method, params)
  if method == "session/notification" or method == "session/update" then
    local update_raw = params.update
    local update_type, update_data = parse_update(update_raw)

    if update_type then
      -- Normalize names: TurnEnd, AgentMessageChunk, ToolCall, ToolCallUpdate
      if self.on_event then
        self.on_event("notification", {
          type = update_type,
          data = update_data,
          sessionId = params.sessionId or params.session_id,
        })
      end
    end
  end
end

--- Handle server-to-client requests
--- @param id any
--- @param method string
--- @param params table
function Client:handle_request(id, method, params)
  -- Standard ACP server-to-client requests (like permission requests) can be handled here.
  -- Currently, hooks use the bridge script, but we will register placeholders.
  local response_payload = rpc_mod.format_response(id, {}, nil)
  self.stdin:write(response_payload)
end

M.Client = Client
return M
