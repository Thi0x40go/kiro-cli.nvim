local M = {}

--- @class KiroRPC
--- @field buffer string internal buffer for raw incoming data
--- @field on_notification fun(method: string, params: table) callback for incoming notifications
--- @field on_request fun(id: any, method: string, params: table) callback for incoming requests
--- @field on_response fun(id: any, result: table|nil, err: table|nil) callback for incoming responses
local RPC = {}
RPC.__index = RPC

--- Create a new RPC parser instance
--- @param callbacks { on_notification: fun(m: string, p: table), on_request: fun(id: any, m: string, p: table), on_response: fun(id: any, r: table|nil, e: table|nil) }
--- @return KiroRPC
function RPC.new(callbacks)
  local self = setmetatable({}, RPC)
  self.buffer = ""
  self.on_notification = callbacks.on_notification
  self.on_request = callbacks.on_request
  self.on_response = callbacks.on_response
  return self
end

--- Feed a new string chunk of raw stdout data into the parser buffer
--- @param chunk string
function RPC:feed(chunk)
  if not chunk or chunk == "" then return end
  self.buffer = self.buffer .. chunk

  while true do
    -- Find header-body delimiter \r\n\r\n
    local header_end = self.buffer:find("\r\n\r\n", 1, true)
    if not header_end then
      break
    end

    local headers = self.buffer:sub(1, header_end - 1)
    
    -- Extract Content-Length
    local content_length_str = headers:match("Content%-Length:%s*(%d+)")
    if not content_length_str then
      -- If we have headers but no Content-Length, it is a malformed message
      -- Remove headers to recover
      self.buffer = self.buffer:sub(header_end + 4)
      goto continue
    end

    local content_length = tonumber(content_length_str)
    local body_start = header_end + 4
    local total_needed = body_start + content_length - 1

    -- If we don't have the full body yet, wait for more data
    if #self.buffer < total_needed then
      break
    end

    -- Extract body and advance buffer
    local body = self.buffer:sub(body_start, total_needed)
    self.buffer = self.buffer:sub(total_needed + 1)

    -- Decode JSON body safely
    local ok, msg = pcall(vim.json.decode, body)
    if not ok then
      vim.notify("[Kiro RPC] Failed to decode JSON-RPC payload: " .. tostring(body), vim.log.levels.ERROR)
      goto continue
    end

    -- Dispatch JSON-RPC message
    if msg.method then
      if msg.id ~= nil then
        -- Request from agent
        if self.on_request then
          self.on_request(msg.id, msg.method, msg.params or {})
        end
      else
        -- Notification from agent
        if self.on_notification then
          self.on_notification(msg.method, msg.params or {})
        end
      end
    elseif msg.id ~= nil then
      -- Response from agent to our request
      if self.on_response then
        self.on_response(msg.id, msg.result, msg.error)
      end
    end

    ::continue::
  end
end

--- Format a JSON-RPC request to be sent over stdio
--- @param id any
--- @param method string
--- @param params table
--- @return string framed_payload
function M.format_request(id, method, params)
  local payload = vim.json.encode({
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params,
  })
  return string.format("Content-Length: %d\r\n\r\n%s", #payload, payload)
end

--- Format a JSON-RPC response to be sent over stdio
--- @param id any
--- @param result table|nil
--- @param err table|nil
--- @return string framed_payload
function M.format_response(id, result, err)
  local msg = {
    jsonrpc = "2.0",
    id = id,
  }
  if err then
    msg.error = err
  else
    msg.result = result or vim.NIL
  end
  local payload = vim.json.encode(msg)
  return string.format("Content-Length: %d\r\n\r\n%s", #payload, payload)
end

--- Format a JSON-RPC notification to be sent over stdio
--- @param method string
--- @param params table
--- @return string framed_payload
function M.format_notification(method, params)
  local payload = vim.json.encode({
    jsonrpc = "2.0",
    method = method,
    params = params,
  })
  return string.format("Content-Length: %d\r\n\r\n%s", #payload, payload)
end

M.RPC = RPC
return M
