local M = {}

--- Read current buffer lines
--- @return string name, string content
function M.get_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    return "scratch", ""
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return vim.fn.fnamemodify(filepath, ":~:."), table.concat(lines, "\n")
end

--- Get compiler and LSP diagnostics for the current buffer
--- @return string
function M.get_diagnostics()
  local bufnr = vim.api.nvim_get_current_buf()
  local diags = vim.diagnostic.get(bufnr)
  if #diags == 0 then return "" end

  local lines = { "LSP Diagnostics in current buffer:" }
  for _, d in ipairs(diags) do
    local severity = "INFO"
    if d.severity == vim.diagnostic.severity.ERROR then
      severity = "ERROR"
    elseif d.severity == vim.diagnostic.severity.WARN then
      severity = "WARNING"
    end
    table.insert(lines, string.format("  - Line %d: [%s] %s", d.lnum + 1, severity, d.message))
  end
  return table.concat(lines, "\n")
end

--- Parse Treesitter structure in the current buffer
--- @return string
function M.get_treesitter_symbols()
  local bufnr = vim.api.nvim_get_current_buf()
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then return "" end
  
  local tree = parser:parse()[1]
  if not tree then return "" end
  local root = tree:root()
  local lang = parser:lang()

  -- Simple query for functions/classes/methods
  local query_str = ""
  if lang == "lua" then
    query_str = "((function_declaration) @symbol) ((function_definition) @symbol)"
  elseif lang == "javascript" or lang == "typescript" or lang == "typescriptreact" or lang == "javascriptreact" then
    query_str = "((function_declaration) @symbol) ((class_declaration) @symbol) ((method_definition) @symbol) ((arrow_function) @symbol)"
  elseif lang == "python" then
    query_str = "((function_definition) @symbol) ((class_definition) @symbol)"
  elseif lang == "rust" then
    query_str = "((function_item) @symbol) ((struct_item) @symbol) ((impl_item) @symbol) ((trait_item) @symbol)"
  elseif lang == "go" then
    query_str = "((function_declaration) @symbol) ((method_declaration) @symbol) ((type_declaration) @symbol)"
  else
    query_str = "((function_definition) @symbol) ((class_definition) @symbol)"
  end

  local ok_q, query = pcall(vim.treesitter.query.parse, lang, query_str)
  if not ok_q or not query then return "" end

  local symbols = {}
  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local range = { node:range() }
    local start_line = range[1]
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, start_line + 1, false)
    if lines[1] then
      table.insert(symbols, string.format("  - Line %d: %s", start_line + 1, vim.trim(lines[1])))
    end
  end

  if #symbols == 0 then return "" end
  return "Treesitter Code Symbols:\n" .. table.concat(symbols, "\n")
end

--- Get Git diff stat asynchronously using vim.loop.spawn
--- @param callback fun(diff_stat: string)
function M.get_git_diff(callback)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  local handle
  local output = ""

  handle = vim.loop.spawn("git", {
    args = { "diff", "--stat" },
    stdio = { nil, stdout, stderr },
    cwd = vim.fn.getcwd()
  }, function(code, signal)
    if handle then handle:close() end
    vim.schedule(function()
      if code == 0 then
        callback(vim.trim(output))
      else
        callback("")
      end
    end)
  end)

  if not handle then
    callback("")
    return
  end

  stdout:read_start(function(err, data)
    if data then output = output .. data end
  end)
end

--- Assemble unified markdown context for Kiro CLI
--- @return string
function M.get_context()
  local context_parts = {}

  -- 1. Current Buffer Info
  local name, content = M.get_current_buffer()
  if name ~= "scratch" and content ~= "" then
    table.insert(context_parts, string.format("### Active Editor Buffer: `%s`", name))
    -- Truncate content if file is very large to avoid context bloating
    local max_chars = 10000
    if #content > max_chars then
      content = content:sub(1, max_chars) .. "\n... [Content Truncated due to size] ..."
    end
    table.insert(context_parts, "```" .. (vim.bo.filetype or "") .. "\n" .. content .. "\n```")
  end

  -- 2. LSP Diagnostics
  local diagnostics = M.get_diagnostics()
  if diagnostics ~= "" then
    table.insert(context_parts, "### LSP Diagnostics\n" .. diagnostics)
  end

  -- 3. Treesitter symbols
  local ts_symbols = M.get_treesitter_symbols()
  if ts_symbols ~= "" then
    table.insert(context_parts, "### Outline Structure\n" .. ts_symbols)
  end

  -- Return compiled context synchronically for current states.
  -- (Git diff is async, we can inject git diff stats when using commands)
  return table.concat(context_parts, "\n\n")
end

return M
