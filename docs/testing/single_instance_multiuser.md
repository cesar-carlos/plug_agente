# Teste de Instância Única - Cenário Multiusuário

Este documento descreve como validar o comportamento de instância única em cenários com múltiplos usuários Windows (Fast User Switching, RDP, sessões diferentes).

## Requisito

Apenas uma instância do Plug Agente por **computador**, independente do usuário ou sessão.

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

### 4. Mutex Global vs Local

- **Global**: Funciona entre sessões (usuários diferentes na mesma máquina).
- **Local**: Funciona apenas na mesma sessão.
- O runner tenta `Global\` primeiro; se falhar (ex.: permissão), usa `Local\` como fallback.
- Em cenários multiusuário, `Global\` é necessário para garantir uma instância por máquina.

## Como Executar

1. Configure duas contas de usuário Windows na mesma máquina.
2. Siga os cenários acima manualmente.
3. Verifique que a MessageBox mostra usuário e nome da máquina corretos.
4. Verifique que o startup automático não exibe mensagem quando o app já está aberto.
