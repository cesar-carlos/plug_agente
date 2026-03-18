# Requisitos do Sistema - Plug Agente

Requisitos para instalação e execução do **Plug Agente** no Windows.

## Requisitos Mínimos

| Item | Especificação |
|------|---------------|
| **Sistema operacional** | Windows 10 ou superior (64 bits) |
| **Arquitetura** | x64 |
| **Memória RAM** | 4 GB |
| **Espaço em disco** | 500 MB |
| **Permissões** | Administrador para instalação |

## Matriz de Compatibilidade (SO)

| Plataforma | Versão | Status | Modo de Execução |
|------------|--------|--------|------------------|
| Windows (cliente) | Windows 10 e Windows 11 | Suporte completo | Completo (todos os recursos) |
| Windows Server | 2012 / 2012 R2 | Suporte degradado | Degradado (sem tray/notificações/auto-update) |
| Windows Server | 2016 ou superior | Suporte degradado | Degradado (sem tray/notificações/auto-update) |
| Windows (cliente) | Windows 8 / 8.1 | Suporte degradado | Degradado |
| Windows (qualquer) | Windows 7 ou inferior | Não suportado | Não inicializa |

### Modo Degradado

No modo degradado, o aplicativo executa com os seguintes recursos desabilitados:
- **Tray (bandeja do sistema)**: Ícone e menu de contexto não disponíveis
- **Notificações locais**: Sistema de notificações Windows desabilitado (usa logging interno)
- **Auto-update**: Verificação automática de atualizações desabilitada
- **Minimize-to-tray**: Janela minimiza normalmente (não para a bandeja)

Recursos que **permanecem funcionais** no modo degradado:
- Core do agente (Socket.IO + ODBC)
- Todas as funcionalidades de query (SQL normal e streaming)
- Configuração e gerenciamento de conexões
- Playground SQL
- Conexão com hub remoto

Notas:
- O app detecta automaticamente a versão do Windows e ajusta suas capacidades
- Banner de modo degradado aparece na UI quando aplicável
- Em ambientes de servidor, valide GPO, permissões, Visual C++ Redistributable e drivers ODBC

## Dependências de Software

### Visual C++ Redistributable

O instalador Inno Setup pode incluir ou verificar o **Microsoft Visual C++ Redistributable** (x64). Se não estiver instalado, o instalador tentará instalá-lo automaticamente.

- Download manual: https://aka.ms/vs/17/release/vc_redist.x64.exe

### ODBC (Open Database Connectivity)

O Plug Agente utiliza ODBC para conexão com bancos de dados. É necessário:

- **Driver ODBC** do banco de dados que você pretende conectar (SQL Server, PostgreSQL, MySQL, etc.)
- Drivers ODBC geralmente vêm com a instalação do próprio banco ou podem ser baixados separadamente

### Rede (opcional)

- **Socket.IO**: Conexão com servidor remoto (se configurado)
- **Internet**: Para verificação de atualizações automáticas

## Verificação Pós-Instalação

Para verificar se a instalação está correta:

1. Execute o Plug Agente pelo menu Iniciar
2. Acesse **Configurações** e teste uma conexão ODBC
3. Verifique os logs em `C:\ProgramData\PlugAgente\logs\` em caso de erros

---

## Checklist de Homologação por Plataforma

Use esta seção como checklist operacional de compatibilidade.

### Pré-requisitos

- [ ] Visual C++ Redistributable instalado
- [ ] Driver ODBC do banco instalado
- [ ] Permissões de administrador para instalação
- [ ] Recursos mínimos (4 GB RAM, 500 MB disco)

### Windows 10/11 (modo completo)

#### Inicialização
- [ ] Aplicativo inicia sem erros
- [ ] Log mostra `Runtime mode: Completo`
- [ ] Janela abre com tamanho esperado
- [ ] Ícone aparece na bandeja
- [ ] Banner de modo degradado não aparece

#### Funcionalidades core
- [ ] Dashboard carrega corretamente
- [ ] Playground SQL (normal e streaming) funciona
- [ ] Configuração/teste de conexão ODBC funciona
- [ ] Conexão com hub Socket.IO funciona

#### Funcionalidades desktop
- [ ] Minimize-to-tray funciona
- [ ] Close-to-tray funciona
- [ ] Menu da bandeja funciona (Abrir/Sair)
- [ ] Notificações locais aparecem

### Windows Server 2012+ e Windows 8/8.1 (modo degradado)

#### Inicialização
- [ ] Aplicativo inicia sem crash
- [ ] Log mostra `Runtime mode: Degradado`
- [ ] Banner de modo degradado aparece com motivos

#### Core (deve funcionar)
- [ ] Dashboard e Playground funcionam
- [ ] SQL streaming funciona
- [ ] ODBC e Socket.IO funcionam

#### Desktop (deve estar desabilitado/noop)
- [ ] Sem ícone de bandeja
- [ ] Minimize/close sem redirecionar para tray
- [ ] Sem notificações locais
- [ ] Sem erros de tray/notificações no log

### Windows abaixo de 8 / Server 2012 (não suportado)

- [ ] App não inicializa core
- [ ] Log mostra `Runtime mode: Não suportado`
- [ ] Mensagem de erro clara de versão mínima

### Testes de estresse (todos os modos com suporte)

- [ ] Query grande (resultado volumoso) sem crash
- [ ] Streaming multi-chunk estável
- [ ] Reconexão Socket.IO após perda de rede
- [ ] Pool ODBC recupera de erro de conexão
- [ ] Encerramento do app é gracioso

### Logs esperados

#### Modo completo
```text
Setting up dependencies with runtime mode: Completo
Registering TrayManagerService
Registering NotificationService
Window manager initialized
Tray manager initialized
Notification service initialized
```

#### Modo degradado
```text
Setting up dependencies with runtime mode: Degradado
Registering NoopTrayManagerService (degraded mode)
Registering NoopNotificationService (degraded mode)
Window manager initialized
Tray manager not available in degraded mode
Notification service initialized
```

#### Modo não suportado
```text
Runtime mode: Não suportado
Cannot run application: Sistema operacional abaixo do mínimo suportado ...
```
