# Plug Agente

Agente Windows com Socket.IO + ODBC para monitoramento e execução de consultas SQL.

## 📋 Sobre o Projeto

O **Plug Agente** é uma aplicação desktop Windows que atua como agente intermediário entre um hub central e bancos de dados locais. O agente recebe requisições de consultas SQL via Socket.IO, executa-as em bancos de dados ODBC (SQL Server, SQL Anywhere) e retorna os resultados comprimidos.

## 🏗️ Arquitetura

O projeto segue **Clean Architecture + Domain Driven Design (DDD)** com separação clara de responsabilidades:

```
┌─────────────────────────────────────────────────────────┐
│         Presentation Layer (UI + State)                │
│  (Pages, Widgets, Providers, Controllers)             │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│        Application Layer (Orquestração)                 │
│  (Services, Use Cases, DTOs, Mappers, Validation)       │
└─────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│          Domain Layer (Lógica de Negócio)               │
│  (Entities, Value Objects, Use Cases,                    │
│   Repository Interfaces, Errors)                         │
└─────────────────────────────────────────────────────────┘
                        ↑
┌─────────────────────────────────────────────────────────┐
│      Infrastructure Layer (Implementação)                │
│  (Data Sources, Repositories, External Services,         │
│   Models, Compression)                                    │
└─────────────────────────────────────────────────────────┘
```

### Regras de Dependência

- ✅ **Domain**: Independente, não depende de frameworks ou outras camadas
- ✅ **Application**: Depende apenas de `domain` e `core`
- ✅ **Infrastructure**: Implementa interfaces do `domain`
- ✅ **Presentation**: Depende de `domain`, `application` e `core`
- ✅ **Core/Shared**: Podem ser usados por qualquer camada

> 📖 Para detalhes completos sobre estrutura, barrel files e regras de importação, consulte [project_structure.md](project_structure.md)

## ✨ Funcionalidades

- ✅ **Conexão Socket.IO**: Comunicação bidirecional em tempo real com hub central
- ✅ **Execução de Consultas SQL**: Processa requisições com bancos via ODBC
- ✅ **Compressão de Dados**: Compacta resultados com gzip para otimizar transmissão
- ✅ **Interface Fluent UI**: Aplicação desktop Windows com design moderno
- ✅ **Sistema Tray**: Integração com área de notificação do Windows
- ✅ **Configuração Local**: Armazena configurações em SQLite com Drift ORM
- ✅ **Tema Padronizado**: Cores e estilos consistentes em `core/theme/app_colors.dart`
- ✅ **Barrel Files**: Imports simplificados através de arquivos barrel

## 🛠️ Tecnologias Principais

### Core

- **Dart** 3.10.4+ e **Flutter** 3.10.4+
- **result_dart** 2.1.1 - Tratamento de erros com pattern Result/Failure
- **get_it** 7.6.7 - Injeção de dependências
- **provider** 6.1.2 - Gerenciamento de estado

### Comunicação e Dados

- **socket_io_client** 2.0.3+1 - Comunicação em tempo real
- **dio** 5.4.0 - Cliente HTTP com interceptors
- **archive** 3.4.9 - Compressão gzip
- **drift** 2.22.1 - ORM para SQLite
- **sqlite3_flutter_libs** 0.5.28 - SQLite para Flutter

### UI Desktop

- **fluent_ui** 4.13.0 - Componentes Fluent Design para Windows
- **window_manager** 0.5.1 - Gerenciamento de janelas
- **tray_manager** 0.5.2 - Integração com system tray

> 📦 Para lista completa de dependências e versões, consulte [dependencies.md](dependencies.md)

## 🚀 Instalação

### Pré-requisitos

- **Flutter SDK** 3.10.4 ou superior
- **Windows** 10 ou superior
- **ODBC Drivers** instalados (SQL Server, SQL Anywhere)

### Passos

1. **Clone o repositório**:

   ```bash
   git clone <repository-url>
   cd plug_agente
   ```

2. **Instale as dependências**:

   ```bash
   flutter pub get
   ```

3. **Gere código do Drift** (se necessário):

   ```bash
   flutter packages pub run build_runner build
   ```

4. **Execute a aplicação**:
   ```bash
   flutter run -d windows
   ```

## ⚙️ Configuração

### Variáveis de Ambiente

Crie um arquivo `.env` na raiz do projeto:

```env
# API Configuration
API_URL=https://api.example.com
HUB_URL=wss://api.example.com/hub
UPDATE_URL=https://api.example.com/updates

# Agent Configuration
AGENT_ID=plug-agent-windows
AGENT_NAME=Plug Agente

# Database Configuration
DB_DRIVER=SQL Server
DB_HOST=localhost
DB_PORT=1433
DB_NAME=
DB_USERNAME=
DB_PASSWORD=

# Connection Configuration
CONNECTION_TIMEOUT=30
QUERY_TIMEOUT=60
RECONNECT_INTERVAL=5
MAX_RECONNECT_ATTEMPTS=10
```

### Configuração do Banco de Dados

1. Abra a aplicação
2. Navegue até a página de **Configuração**
3. Preencha os dados de conexão:
   - Driver (SQL Server ou SQL Anywhere)
   - Host e Porta
   - Nome do banco de dados
   - Usuário e senha
4. Clique em **Testar Conexão** para validar
5. Salve a configuração

## 📖 Uso

### Primeiro Uso

1. Execute o aplicativo
2. Configure a conexão com o banco de dados na página de Configuração
3. Teste a conexão para validar as credenciais
4. O agente conectará automaticamente ao hub quando configurado

### Monitoramento

- **Dashboard**: Visualize o status da conexão e estatísticas
- **Configuração**: Gerencie conexões de banco de dados
- **Tray**: Acesse o menu rápido na área de notificação

> 🔄 Para entender o fluxo de dados completo, consulte [data_flow.md](data_flow.md)

## 🎨 Tema e Cores

O tema está padronizado em `core/theme/app_colors.dart`:

```dart
class AppColors {
  static const Color primary = Color(0xFF0078D4);
  static const Color secondary = Color(0xFF2E7D32);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFFF5252);
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFF3F4F6);
}
```

## 📚 Documentação Adicional

- **[Estrutura do Projeto](project_structure.md)**: Documentação detalhada da estrutura de pastas, barrel files e regras de importação
- **[Dependências](dependencies.md)**: Tabela completa de dependências e versões recomendadas
- **[Fluxo de Dados](data_flow.md)**: Diagrama explicativo do fluxo de dados e componentes

## 🔧 Desenvolvimento

### Convenções de Nomenclatura

- **Arquivos**: `snake_case.dart`
- **Classes**: `PascalCase`
- **Interfaces**: `I` + `PascalCase` (ex: `IAgentConfigRepository`)
- **Variáveis/Métodos**: `camelCase`
- **Constantes**: `camelCase` com `const` ou `static const`

> 📋 Para regras completas de importação e desenvolvimento, consulte [project_structure.md](project_structure.md)

### Build e Deploy

```bash
# Build para Windows
flutter build windows

# Build com release
flutter build windows --release
```

## 🐛 Troubleshooting

### Problemas Comuns

1. **Erro de conexão ODBC**:

   - Verifique se os drivers ODBC estão instalados
   - Confirme as credenciais do banco de dados
   - Teste a conexão diretamente no Windows

2. **Erro de Socket.IO**:

   - Verifique a URL do hub no arquivo `.env`
   - Confirme que o servidor está acessível
   - Verifique logs em `core/logger/app_logger.dart`

3. **Erro de compilação**:
   - Execute `flutter clean`
   - Execute `flutter pub get`
   - Gere código do Drift: `flutter packages pub run build_runner build`

## 📝 Licença

MIT License - Consulte o arquivo LICENSE para detalhes.

## 🤝 Contribuindo

1. Siga as regras de arquitetura definidas em `.cursor/rules/`
2. Mantenha a separação de camadas
3. Use barrel files para imports
4. Documente mudanças significativas
5. Siga as convenções de nomenclatura

---

**Desenvolvido com Clean Architecture + DDD** 🏗️
