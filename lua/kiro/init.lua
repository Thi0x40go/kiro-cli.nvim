-- Kiro CLI Neovim Plugin (Snacks Edition)
-- Native integration with Kiro CLI through persistent terminals

local M = {}

local DEFAULT_CONFIG = {
  trust_all_tools = true,
}

M.config = {}

function M.toggle(opts)
  opts = opts or {}
  local position = opts.position or "float"
  
  local cmd = "kiro-cli chat"
  if M.config.trust_all_tools then
    cmd = cmd .. " --trust-all-tools"
  end

  -- Usa a API do Snacks para gerenciar o terminal persistente
  if pcall(require, "snacks") then
    require("snacks").terminal.toggle(cmd, {
      win = {
        position = position,
        title = " Kiro CLI ",
      },
    })
  else
    vim.notify("Plugin 'snacks.nvim' não encontrado. Ele é necessário para o Kiro.", vim.log.levels.ERROR)
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})

  -- Cria comandos de usuário
  vim.api.nvim_create_user_command("KiroToggle", function() M.toggle({ position = "float" }) end, {})
  vim.api.nvim_create_user_command("KiroSplit", function() M.toggle({ position = "bottom" }) end, {})
end

return M
