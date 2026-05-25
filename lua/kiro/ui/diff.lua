local M = {}

--- Read contents of a file safely
--- @param filepath string
--- @return string
local function read_file(filepath)
  local f = io.open(filepath, "r")
  if not f then return "" end
  local content = f:read("*a")
  f:close()
  return content
end

--- Get a unified diff string between original file and new content
--- @param filepath string
--- @param new_content string
--- @return string
function M.get_diff_string(filepath, new_content)
  local original = read_file(filepath)
  local diff = vim.diff(original, new_content, { result_type = "unified" })
  if not diff or diff == "" then
    return "No changes proposed."
  end
  return diff
end

--- Render unified diff in a buffer with syntax highlighting
--- @param bufnr number
--- @param filepath string
--- @param new_content string
function M.render_unified(bufnr, filepath, new_content)
  local diff_str = M.get_diff_string(filepath, new_content)
  local lines = vim.split(diff_str, "\n")
  
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("filetype", "diff", { buf = bufnr })
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
end

--- Render side-by-side diff using Neovim's native diff mode
--- @param parent_win number window to split next to
--- @param filepath string
--- @param new_content string
--- @return number win_orig, number win_new, number buf_orig, number buf_new
function M.render_side_by_side(parent_win, filepath, new_content)
  local original_text = read_file(filepath)
  local filename = vim.fn.fnamemodify(filepath, ":t")

  -- Create two scratch buffers
  local buf_orig = vim.api.nvim_create_buf(false, true)
  local buf_new = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(buf_orig, 0, -1, false, vim.split(original_text, "\n"))
  vim.api.nvim_buf_set_lines(buf_new, 0, -1, false, vim.split(new_content, "\n"))

  -- Determine filetype from extension to get syntax highlighting
  local ft = vim.filetype.match({ filename = filepath }) or "text"
  vim.api.nvim_set_option_value("filetype", ft, { buf = buf_orig })
  vim.api.nvim_set_option_value("filetype", ft, { buf = buf_new })

  -- Buffer names for aesthetics
  vim.api.nvim_buf_set_name(buf_orig, "Original (" .. filename .. ")")
  vim.api.nvim_buf_set_name(buf_new, "Proposed (" .. filename .. ")")

  -- Split windows
  local current_win = vim.api.nvim_get_current_win()
  
  -- Create left window (original)
  vim.api.nvim_set_current_win(parent_win)
  vim.cmd("vsplit")
  local win_orig = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win_orig, buf_orig)
  vim.api.nvim_win_set_config(win_orig, { title = " Original " })

  -- Create right window (proposed)
  vim.cmd("vsplit")
  local win_new = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win_new, buf_new)
  vim.api.nvim_win_set_config(win_new, { title = " Proposed (Kiro Changes) " })

  -- Set diff mode in both windows
  vim.api.nvim_win_call(win_orig, function() vim.cmd("diffthis") end)
  vim.api.nvim_win_call(win_new, function() vim.cmd("diffthis") end)

  -- Set buffers unmodifiable
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf_orig })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf_new })

  -- Return focus to parent or right window
  vim.api.nvim_set_current_win(win_new)

  return win_orig, win_new, buf_orig, buf_new
end

return M
