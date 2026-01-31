# Dependências do Plug Agente

Este documento documenta as dependências do projeto Plug Agente e suas versões recomendadas.

## Dependências Principais

### Navegação e Rotas

- **go_router**: ^14.6.2
  - Sistema de rotas declarativo para Flutter
  - Usado para navegação entre páginas da aplicação
  - Suporta deep linking e navegação declarativa

### Comunicação

- **socket_io_client**: ^2.0.3+1
  - Cliente Socket.IO para comunicação com o hub
  - Usado para comunicação em tempo real entre o agente e o servidor central

### Compressão

- **archive**: ^3.4.9
  - Biblioteca para compressão e descompressão de dados usando gzip
  - Reduz o tamanho dos pacotes transmitidos

### Banco de Dados via ODBC

- **dart_odbc**: ^0.1.2 (comentado para investigação)
  - Conector ODBC para acesso a bancos de dados como SQL Server e SQL Anywhere
  - Implementação temporária usando MockDatabaseGateway até que a dependência seja resolvida

### Configuração Local (SQLite)

- **drift**: ^2.22.1
  - ORM para acesso ao SQLite local para armazenar configurações
  - Geração de código type-safe para queries
- **sqlite3_flutter_libs**: ^0.5.28
  - Biblioteca SQLite para Flutter
  - Fornece binários nativos do SQLite
- **path_provider**: ^2.1.5
  - Para encontrar caminhos para armazenamento local
  - Acesso a diretórios do sistema (documents, cache, etc.)
- **path**: ^1.9.1
  - Utilitários para manipulação de caminhos de arquivos
  - Cross-platform path handling
- **shared_preferences**: ^2.5.4
  - Armazenamento simples de preferências chave-valor
  - Persistência de configurações simples

### Injeção de Dependências

- **get_it**: ^7.6.7
  - Localizador de serviços para injeção de dependências
  - Service locator pattern implementation
- **provider**: ^6.1.2
  - Gerenciamento de estado com ChangeNotifier
  - State management reativo

### UI Desktop (Windows)

- **fluent_ui**: ^4.13.0
  - Biblioteca de componentes Fluent Design para Windows
  - Design system moderno da Microsoft
- **fluentui_system_icons**: ^1.1.273
  - Ícones do sistema Fluent Design
  - Conjunto completo de ícones para Windows
- **window_manager**: ^0.5.1
  - Gerenciamento de janelas do aplicativo
  - Controle de tamanho, posição e estado das janelas
- **tray_manager**: ^0.5.2
  - Integração com a área de notificação do sistema
  - Menu tray e notificações do sistema

### Estado e Validação

- **result_dart**: ^2.1.1
  - Tratamento de resultados com pattern Result/Failure
  - Functional error handling
- **zard**: ^0.0.25
  - Validação de dados com schema Zard
  - Schema-based validation

### Sistema Tray

- **tray_manager**: ^0.5.2
  - Integração com a área de notificação do sistema
  - Menu contextual e notificações

### Configuração e Variáveis de Ambiente

- **flutter_dotenv**: ^5.1.0
  - Carregamento de variáveis de ambiente de arquivo .env
  - Configuração externa da aplicação
- **uuid**: ^4.3.3
  - Geração de identificadores únicos
  - UUID v4 generation

### Log e Debug

- **logger**: ^2.1.0
  - Sistema de logging para depuração
  - Logging estruturado e colorido

### Notificações e Updates

- **package_info_plus**: ^4.2.0
  - Informações sobre o pacote
  - Versão e informações da aplicação
- **auto_updater**: ^0.2.1
  - Sistema de atualização automática
  - Update checking e download

### Criptografia e Segredos

- **crypto**: ^3.0.6
  - Funções criptográficas
  - Hashing e criptografia
- **flutter_secure_storage**: ^9.0.0
  - Armazenamento seguro de credenciais
  - Keychain/Keystore integration

### HTTP Client

- **dio**: ^5.4.0
  - Cliente HTTP poderoso para Dart
  - Suporte a interceptors, cancelamento e timeouts
  - Usado para requisições HTTP e interceptors

### E-mail (SMTP)

- **mailer**: ^6.6.0
  - Cliente SMTP para envio de e-mails
  - Suporte a autenticação e anexos

### Notificações Locais

- **flutter_local_notifications**: ^19.5.0
  - Notificações locais do sistema
  - Notificações agendadas e em tempo real

### Gráficos

- **fl_chart**: ^1.1.1
  - Biblioteca de gráficos para Flutter
  - Gráficos de linha, barra, pizza, etc.

### Utilitários do Sistema

- **win32**: ^5.15.0
  - Bindings para APIs do Windows
  - Acesso a funcionalidades nativas do Windows
- **ffi**: ^2.1.5
  - Foreign Function Interface para Dart
  - Chamadas a bibliotecas nativas
- **collection**: ^1.19.1
  - Utilitários para coleções Dart
  - Funções auxiliares para listas, maps, etc.

### Ícones

- **cupertino_icons**: ^1.0.8
  - Ícones do iOS/Cupertino
  - Conjunto padrão de ícones

## Dependências de Desenvolvimento

### Testes

- **flutter_test**: SDK Flutter
  - Framework de testes para Flutter
  - Widget tests e unit tests
- **test**: ^1.25.8
  - Framework de testes unitários para Dart
  - Testes assíncronos e mocks
- **mocktail**: ^1.0.4
  - Biblioteca de mocking para testes
  - Criação de mocks type-safe

### Linting e Análise

- **flutter_lints**: ^5.0.0
  - Conjunto de regras de lint para Flutter
  - Análise estática de código

### Build e Geração de Código

- **drift_dev**: ^2.22.1
  - Gerador de código para Drift ORM
  - Geração de código type-safe
- **build_runner**: ^2.4.13
  - Ferramenta para executar code generators
  - Execução de build scripts
- **protoc_plugin**: ^25.0.0
  - Plugin para Protocol Buffers
  - Geração de código a partir de .proto files

### Utilitários de Build

- **flutter_launcher_icons**: ^0.13.1
  - Geração automática de ícones do launcher
  - Ícones para diferentes plataformas

## Recomendações de Versão

Para cada dependência, recomendamos manter as versões mais recentes estáveis enquanto houver compatibilidade:

- **socket_io_client**: Manter na versão mais recente para suporte aos últimos protocolos WebSocket
- **archive**: Usar versão estável para melhor compressão
- **get_it**: Versão mais recente para melhor suporte à injeção
- **fluent_ui**: Manter na versão mais recente para atualizações da UI Fluent
- **drift**: Versão mais recente para correções de bug e melhorias de performance
- **go_router**: Manter atualizado para suporte a novas funcionalidades de navegação
- **dio**: Versão estável para melhor suporte a interceptors e cancelamento

## Notas de Implementação

1. **Otimização de Performance**: Os componentes Fluent UI devem usar const construtores sempre que possível
2. **Tratamento de Erros**: Usar sempre o pattern Result/Failure para tratamento consistente de erros
3. **Clean Architecture**: Seguir rigorosamente a separação de camadas (Domain, Application, Infrastructure, Presentation)
4. **Testabilidade**: Implementar testes unitários para cada camada e testes de integração
5. **Segurança**: Credenciais devem ser armazenadas usando flutter_secure_storage
6. **Nomenclatura**: Seguir padrão PascalCase para classes e camelCase para métodos e variáveis
7. **Navegação**: Usar go_router para toda navegação, nunca Navigator.push diretamente
8. **HTTP**: Usar dio para todas as requisições HTTP, nunca o pacote http

## Tabela de Compatibilidade

| Componente                  | Versão Mínima | Versão Recomendada | Notas                     |
| --------------------------- | ------------- | ------------------ | ------------------------- |
| fluent_ui                   | 4.5.0         | 4.13.0+            | UI modern para Windows    |
| socket_io_client            | 1.0.0         | 2.0.3+1            | Comunicação em tempo real |
| archive                     | 3.0.0         | 3.4.9              | Melhor compressão         |
| get_it                      | 7.0.0         | 7.6.7+             | Injeção de dependências   |
| drift                       | 2.0.0         | 2.22.1             | ORM para SQLite           |
| result_dart                 | 2.0.0         | 2.1.1              | Tratamento de erros       |
| provider                    | 6.0.0         | 6.1.2+             | Gerenciamento de estado   |
| go_router                   | 14.0.0        | 14.6.2+            | Sistema de rotas          |
| dio                         | 5.0.0         | 5.4.0              | Cliente HTTP              |
| window_manager              | 0.3.0         | 0.5.1+             | Gerenciamento de janelas  |
| tray_manager                | 0.2.0         | 0.5.2+             | Sistema tray              |
| flutter_local_notifications | 19.0.0        | 19.5.0+            | Notificações locais       |
| fl_chart                    | 1.0.0         | 1.1.1+             | Gráficos                  |
| mailer                      | 6.0.0         | 6.6.0              | Envio de e-mails          |

## Organização por Categoria

### Comunicação e Rede

- socket_io_client, dio

### Persistência de Dados

- drift, sqlite3_flutter_libs, path_provider, shared_preferences, flutter_secure_storage

### UI e Interface

- fluent_ui, fluentui_system_icons, window_manager, tray_manager, fl_chart

### Navegação

- go_router

### Estado e Validação

- provider, result_dart, zard

### Utilitários

- uuid, logger, crypto, path, collection, win32, ffi

### Configuração

- flutter_dotenv, package_info_plus

### Notificações e Comunicação Externa

- flutter_local_notifications, mailer, auto_updater

### Desenvolvimento

- flutter_lints, drift_dev, build_runner, mocktail, test, protoc_plugin, flutter_launcher_icons

## Próximos Passos

1. Investigar e resolver dependência dart_odbc
2. Implementar testes unitários completos
3. Adicionar integração com banco de dados real
4. Implementar funcionalidades de compressão avançadas
5. Otimizar performance da UI
6. Implementar gráficos no dashboard usando fl_chart
7. Adicionar notificações locais para eventos importantes
8. Implementar envio de e-mails para alertas críticos
