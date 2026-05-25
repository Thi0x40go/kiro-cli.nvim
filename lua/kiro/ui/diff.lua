local M = {}

--- Setup premium diff highlights
local function setup_highlights()
  local is_dark = vim.o.background == "dark"
  if is_dark then
    vim.api.nvim_set_hl(0, "KiroDiffAdd", { bg = "#143a1d", fg = "#4ade80", default = true })
    vim.api.nvim_set_hl(0, "KiroDiffDelete", { bg = "#441515", fg = "#f87171", default = true })
    vim.api.nvim_set_hl(0, "KiroDiffChange", { bg = "#2b261a", fg = "#fbbf24", default = true })
    vim.api.nvim_set_hl(0, "KiroDiffText", { bg = "#4d3d18", fg = "#ffffff", bold = true, default = true })
  else
    vim.api.nvim_set_hl(0, "KiroDiffAdd", { bg = "#dcfce7", fg = "#166534", default = true })
    vim.api.nvim_set_hl(0, "KiroDiffDelete", { bg = "#fee2e2", fg = "#991b1b", default = true })
    vim.api.nvim_set_hl(0, "KiroDiffChange", { bg = "#fef3c7", fg = "#92400e", default = true })
    vim.api.nvim_set_hl(0, "KiroDiffText", { bg = "#fde68a", fg = "#78350f", bold = true, default = true })
  end
end

--- Apply styling and diffopt options to a diff window
function M.apply_winhighlight(win)
  setup_highlights()
  vim.api.nvim_set_option_value(
    "winhighlight",
    "DiffAdd:KiroDiffAdd,DiffDelete:KiroDiffDelete,DiffChange:KiroDiffChange,DiffText:KiroDiffText",
    { win = win }
  )
  pcall(function()
    vim.api.nvim_set_option_value(
      "diffopt",
      "filler,internal,closeoff,algorithm:histogram,linematch:60",
      { win = win }
    )
  end)
end

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

  -- Determine filetype from extension to get syntax highlighting (safely wrapped)
  local ft = "text"
  pcall(function()
    ft = vim.filetype.match({ filename = filepath }) or "text"
  end)
  vim.api.nvim_set_option_value("filetype", ft, { buf = buf_orig })
  vim.api.nvim_set_option_value("filetype", ft, { buf = buf_new })

  -- Buffer names for aesthetics (safely wrapped to avoid E95 name collisions)
  pcall(vim.api.nvim_buf_set_name, buf_orig, "Original (" .. filename .. ")")
  pcall(vim.api.nvim_buf_set_name, buf_new, "Proposed (" .. filename .. ")")

  -- Calculate sizes for floating windows side-by-side
  local screen_w = vim.o.columns
  local screen_h = vim.o.lines

  local height = math.min(30, screen_h - 6)
  local width = math.floor((screen_w - 6) / 2)
  local row = math.floor((screen_h - height) / 2)

  local col_orig = 2
  local col_new = col_orig + width + 2

  local opts_orig = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col_orig,
    style = "minimal",
    border = "rounded",
    title = " Original (" .. filename .. ") ",
    title_pos = "center",
  }

  local opts_new = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col_new,
    style = "minimal",
    border = "rounded",
    title = " Proposed (" .. filename .. ") ",
    title_pos = "center",
  }

  -- Create floating windows
  local win_orig = vim.api.nvim_open_win(buf_orig, false, opts_orig)
  local win_new = vim.api.nvim_open_win(buf_new, true, opts_new)

  -- Apply premium highlights and diff options
  M.apply_winhighlight(win_orig)
  M.apply_winhighlight(win_new)

  -- Set diff mode in both windows
  vim.api.nvim_win_call(win_orig, function() vim.cmd("diffthis") end)
  vim.api.nvim_win_call(win_new, function() vim.cmd("diffthis") end)

  -- Set buffers unmodifiable
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf_orig })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf_new })

  -- Focus the right window & force exit insert mode
  vim.api.nvim_set_current_win(win_new)
  vim.cmd("stopinsert")

  return win_orig, win_new, buf_orig, buf_new
end

return M
