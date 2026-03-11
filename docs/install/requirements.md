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
