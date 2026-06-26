# kiro.nvim

Plugin do Neovim para integração do Kiro CLI via popups do tmux.

## Requisitos

- Neovim 0.8+
- tmux 3.2+
- [Kiro CLI](https://docs.aws.amazon.com/kiro/)

## Instalação

### lazy.nvim

```lua
{
  'Thi0x40go/kiro-cli.nvim',
  config = function()
    require('kiro').setup()
  end,
  keys = {
    { '<leader>tk', '<cmd>KiroToggle<cr>', desc = 'Alternar Kiro CLI' },
    { '<leader>kd', '<cmd>KiroDebug<cr>', desc = 'Depurar Kiro' },
    { '<leader>kc', '<cmd>KiroCleanup<cr>', desc = 'Limpar sessões Kiro' },
  },
}
```

## Configuração

```lua
require('kiro').setup({
  trust_all_tools = false,  -- Se true, passa a flag --trust-all-tools
  enable_sound = true,      -- Emitir um som quando o modal de aprovação aparecer
})
```

## Comandos

| Comando | Descrição |
|---------|-----------|
| `:KiroToggle` | Alternar popup do Kiro CLI |
| `:KiroDebug` | Mostrar informações de depuração |
| `:KiroCleanup` | Finalizar todas as sessões do Kiro |

## Mapeamento de Teclas

Mapeamentos sugeridos (adicione à sua configuração):

```lua
vim.keymap.set('n', '<leader>tk', '<cmd>KiroToggle<cr>', { desc = 'Alternar Kiro CLI' })
```

## Uso

1. Abra o Neovim dentro do tmux
2. Pressione `<leader>tk` para abrir a popup do Kiro CLI
3. Use o prefixo do tmux + `d` para fechar o popup (a sessão continuará ativa)

## Aprovação de Ferramentas (Security Gate)

O `kiro-cli.nvim` fornece um script de gancho (hook) para interceptar requisições de uso de ferramentas pelo Kiro CLI e solicitar a sua aprovação diretamente no Neovim através de um modal flutuante.

### 1. Configurar o Hook no Kiro CLI

Para registrar o hook, edite o arquivo de configuração do seu agente Kiro CLI (por exemplo, `~/.kiro/agents/kiro_default.json`, ou crie-o se não existir) e adicione o hook `preToolUse`:

```json
{
  "hooks": {
    "preToolUse": "node /caminho/absoluto/para/kiro-cli.nvim/hooks/approval.js"
  }
}
```

*(Substitua `/caminho/absoluto/para/kiro-cli.nvim` pelo caminho real onde o plugin está instalado no seu sistema)*

### 2. Configuração no Neovim

Certifique-se de que `trust_all_tools` está definido como `false` na sua configuração do Neovim para que os hooks sejam acionados em vez de ignorar o modal de aprovação:

```lua
require('kiro').setup({
  trust_all_tools = false,
})
```

## Licença

MIT
