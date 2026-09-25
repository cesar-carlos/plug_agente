# Teste de Instância Única - Cenário Multiusuário

Este documento descreve como validar o comportamento de instância única em cenários com múltiplos usuários Windows (Fast User Switching, RDP, sessões diferentes). Implementação: `windows/runner/main.cpp`.

## Requisito

Apenas uma instância do Plug Agente por **computador**, independente do usuário ou sessão (quando o mutex `Global\` está disponível; ver cenário 5).

## Comportamento da segunda instância

| Lançamento | Comportamento esperado |
| --- | --- |
| Com `--autostart` | Encerra silenciosamente, sem MessageBox |
| Manual com deep link (`plugdb://`, `http://`, `https://`) e janela do runner encontrada | Encaminha o link à instância existente (`WM_COPYDATA`) e encerra, sem MessageBox |
| Manual sem deep link, ou janela não encontrada | MessageBox informando que o app já está em execução, com usuário e máquina |

A janela existente é procurada com `FindWindowW`, que só enxerga a sessão atual; entre sessões diferentes o encaminhamento de deep link não ocorre e a MessageBox é exibida.

## Cenários de Teste

### 1. Fast User Switching (troca rápida de usuário)

1. Usuário A faz login e abre o Plug Agente.
2. Usuário A faz logoff (ou Win+L) e Usuário B faz login na mesma máquina.
3. Usuário B tenta abrir o Plug Agente.
4. **Esperado**: MessageBox informando que o app já está em execução, com usuário e máquina.

### 2. RDP (Remote Desktop) - duas sessões na mesma máquina

1. Usuário A abre o app na sessão local.
2. Usuário B conecta via RDP na mesma máquina e tenta abrir o app.
3. **Esperado**: MessageBox na sessão do Usuário B informando que o app já está aberto.

### 3. Startup automático com app já aberto

1. Usuário A tem o app aberto.
2. Usuário B faz login (ou o Windows inicia com "Iniciar com o Windows" habilitado para outro usuário).
3. O app é lançado com `--autostart`.
4. **Esperado**: Segunda instância encerra silenciosamente, sem MessageBox.

### 4. Deep link com app já aberto (mesma sessão)

1. Usuário A tem o app aberto.
2. Na mesma sessão, abre um link `plugdb://...` (ou executa o app passando o link como argumento).
3. **Esperado**: A instância existente recebe o link; nenhuma MessageBox e nenhuma segunda janela.

### 5. Mutex Global vs Local

- Nomes: `Global\PlugAgente_SingleInstance` e `Local\PlugAgente_SingleInstance`.
- **Global**: Funciona entre sessões (usuários diferentes na mesma máquina).
- **Local**: Funciona apenas na mesma sessão.
- O runner tenta `Global\` primeiro; se falhar sem evidência de outra instância (ex.: permissão), usa `Local\` como fallback.
- Acesso negado ao mutex `Global\` com a janela do runner presente é tratado como instância existente (cenário de privilégios diferentes).
- Se nenhum mutex puder ser criado, o app segue sem proteção de instância única (`outcome=degraded_no_mutex`).
- Em cenários multiusuário, `Global\` é necessário para garantir uma instância por máquina.
- Diagnóstico: o runner grava `[plug_agente] Single-instance mutex outcome=...` via `OutputDebugString` (visível com DebugView ou debugger).

## Como Executar

1. Configure duas contas de usuário Windows na mesma máquina.
2. Siga os cenários acima manualmente.
3. Verifique que a MessageBox mostra usuário e nome da máquina corretos.
4. Verifique que o startup automático não exibe mensagem quando o app já está aberto.
