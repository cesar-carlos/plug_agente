# Checklist de Homologação - Compatibilidade Windows Server

Este documento contém o checklist para validar a execução do Plug Agente em diferentes versões do Windows.

## Pré-requisitos

- [ ] Visual C++ Redistributable instalado
- [ ] Driver ODBC do banco de dados instalado
- [ ] Permissões de administrador para instalação
- [ ] 4 GB RAM mínimo, 500 MB disco

## Windows 10/11 (Modo Completo)

### Inicialização
- [ ] Aplicativo inicia sem erros
- [ ] Log mostra "Runtime mode: Completo"
- [ ] Janela abre com tamanho correto (1200x800)
- [ ] Ícone aparece na bandeja do sistema
- [ ] Banner de modo degradado **NÃO** aparece

### Funcionalidades Core
- [ ] Dashboard carrega corretamente
- [ ] Playground SQL funciona (query padrão)
- [ ] Playground SQL com streaming funciona
- [ ] Configuração de conexão ODBC funciona
- [ ] Teste de conexão ODBC funciona
- [ ] Conexão com hub Socket.IO funciona

### Funcionalidades Desktop
- [ ] Minimize-to-tray funciona
- [ ] Close-to-tray funciona
- [ ] Clique no ícone da bandeja restaura janela
- [ ] Menu de contexto da bandeja funciona ("Abrir", "Sair")
- [ ] Notificações locais aparecem
- [ ] Aplicativo minimiza/maximiza/fecha normalmente

## Windows Server 2012/2012 R2 (Modo Degradado)

### Inicialização
- [ ] Aplicativo inicia sem erros
- [ ] Log mostra "Runtime mode: Degradado"
- [ ] Log mostra "Tray manager not available in degraded mode"
- [ ] Janela abre com tamanho correto
- [ ] Banner de modo degradado **APARECE** na UI
- [ ] Banner lista motivos da degradação

### Funcionalidades Core (devem funcionar)
- [ ] Dashboard carrega corretamente
- [ ] Playground SQL funciona (query padrão)
- [ ] Playground SQL com streaming funciona
- [ ] Configuração de conexão ODBC funciona
- [ ] Teste de conexão ODBC funciona
- [ ] Conexão com hub Socket.IO funciona

### Funcionalidades Desktop (devem estar desabilitadas/noop)
- [ ] Ícone da bandeja **NÃO** aparece
- [ ] Minimize vai para barra de tarefas (não para tray)
- [ ] Close fecha janela normalmente (não para tray)
- [ ] Notificações **NÃO** aparecem (silent fallback)
- [ ] Logs não mostram erros de tray/notificações

### Validações de Log
- [ ] Sem stack traces de erro relacionados a tray
- [ ] Sem stack traces de erro relacionados a notificações
- [ ] Mensagens "Notification request ignored (degraded mode)" quando tentativa de notificar
- [ ] ODBC inicializa corretamente
- [ ] Pool de conexões funciona

## Windows Server 2016+ (Modo Degradado)

Repetir checklist de Windows Server 2012/2012 R2.

- [ ] Todas as validações de modo degradado passam
- [ ] Banner mostra "Windows Server detectado"

## Windows 8/8.1 (Modo Degradado)

Repetir checklist de modo degradado.

- [ ] Banner mostra "Windows 8/8.1: recursos de desktop podem estar limitados"

## Windows 7 (Não Suportado)

### Validação de Recusa
- [ ] Aplicativo **NÃO** inicia core
- [ ] Log mostra "Runtime mode: Não suportado"
- [ ] Log mostra "Cannot run application" com razões
- [ ] Mensagem de erro clara para usuário

## Testes de Estresse (todos os modos)

- [ ] Query grande (> 50 MB resultado) funciona
- [ ] Streaming de múltiplos chunks funciona
- [ ] Reconexão Socket.IO após perda de rede
- [ ] Pool ODBC recicla após erro de conexão inválida
- [ ] Retry automático em buffer insuficiente
- [ ] Aplicativo fecha graciosamente (sem crash)

## Logs Esperados

### Modo Completo
```
Setting up dependencies with runtime mode: Completo
Registering TrayManagerService
Registering NotificationService
Window manager initialized
Tray manager initialized
Notification service initialized
```

### Modo Degradado
```
Setting up dependencies with runtime mode: Degradado
Degradation reasons: Windows Server 2012/2012 R2: recursos de desktop desabilitados
Registering NoopTrayManagerService (degraded mode)
Registering NoopNotificationService (degraded mode)
Window manager initialized
Tray manager not available in degraded mode
Notification service initialized
```

### Modo Não Suportado
```
Runtime mode: Não suportado
Cannot run application: Sistema operacional abaixo do mínimo suportado, Versão: 6.1.7601, Mínimo requerido: Windows 8 / Server 2012
```

## Notas de Homologação

- Testar em máquina limpa (sem ambiente de desenvolvimento)
- Validar com diferentes drivers ODBC (SQL Server, PostgreSQL, etc.)
- Verificar logs em `C:\ProgramData\PlugAgente\logs\`
- Testar tanto instalação via instalador quanto execução direta do `.exe`
- Validar comportamento com GPO restritivas em ambiente corporativo
