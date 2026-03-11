# Estrutura do Projeto Plug Agente

Este documento descreve a estrutura completa do projeto seguindo Clean Architecture + DDD.

## 📁 Estrutura de Pastas

```
lib/
├── domain/                    # Domain Layer (Lógica de Negócio Pura)
│   ├── entities/             # Entidades do domínio
│   │   ├── config.dart
│   │   ├── query_request.dart
│   │   ├── query_response.dart
│   │   └── entities.dart     # Barrel file
│   ├── value_objects/        # Objetos de valor
│   │   ├── agent_id.dart
│   │   ├── connection_string.dart
│   │   ├── database_driver.dart
│   │   └── value_objects.dart # Barrel file
│   ├── repositories/         # Interfaces de repositórios
│   │   ├── i_agent_config_repository.dart
│   │   ├── i_database_gateway.dart
│   │   ├── i_transport_client.dart
│   │   └── repositories.dart # Barrel file
│   ├── use_cases/           # Casos de uso (quando necessário no Domain)
│   │   └── use_cases.dart   # Barrel file
│   ├── errors/              # Erros específicos do domínio
│   │   ├── failures.dart
│   │   └── errors.dart      # Barrel file
│   └── domain.dart          # Barrel file principal
│
├── application/              # Application Layer (Orquestração)
│   ├── services/            # Serviços de aplicação
│   │   ├── compression_service.dart
│   │   ├── config_service.dart
│   │   ├── connection_service.dart
│   │   ├── query_normalizer_service.dart
│   │   ├── update_service.dart
│   │   └── services.dart    # Barrel file
│   ├── use_cases/          # Casos de uso
│   │   ├── check_for_updates.dart
│   │   ├── connect_to_hub.dart
│   │   ├── execute_playground_query.dart
│   │   ├── execute_streaming_query.dart
│   │   ├── handle_query_request.dart
│   │   ├── load_agent_config.dart
│   │   ├── save_agent_config.dart
│   │   ├── test_db_connection.dart
│   │   └── use_cases.dart   # Barrel file
│   ├── dtos/               # Data Transfer Objects
│   │   └── dtos.dart       # Barrel file
│   ├── mappers/            # Conversores entre entidades e DTOs
│   │   └── mappers.dart    # Barrel file
│   ├── validation/         # Validação de dados
│   │   ├── config_validator.dart
│   │   ├── query_normalizer.dart
│   │   └── validation.dart # Barrel file
│   └── application.dart    # Barrel file principal
│
├── infrastructure/          # Infrastructure Layer (Implementações)
│   ├── datasources/        # Fontes de dados
│   │   ├── agent_config_data_source.dart
│   │   ├── socket_data_source.dart
│   │   └── datasources.dart # Barrel file
│   ├── pool/               # Pool de conexões ODBC
│   │   └── odbc_connection_pool.dart
│   ├── repositories/       # Implementações de repositórios
│   │   ├── agent_config_repository.dart
│   │   ├── agent_config_drift_database.dart
│   │   └── repositories.dart # Barrel file
│   ├── external_services/  # Serviços externos
│   │   ├── mock_database_gateway.dart
│   │   ├── odbc_database_gateway.dart
│   │   ├── odbc_streaming_gateway.dart
│   │   ├── socket_io_transport_client.dart
│   │   ├── interceptors/   # Interceptadores HTTP (dio)
│   │   │   └── interceptors.dart # Barrel file
│   │   └── external_services.dart # Barrel file
│   ├── builders/          # Builders de conexão
│   │   └── odbc_connection_builder.dart
│   ├── models/            # Modelos para serialização
│   │   ├── envelope_model.dart
│   │   └── models.dart    # Barrel file
│   ├── compression/       # Utilitários de compressão
│   │   ├── gzip_compressor.dart
│   │   └── compression.dart # Barrel file
│   └── infrastructure.dart # Barrel file principal
│
├── presentation/           # Presentation Layer (UI)
│   ├── pages/            # Telas da aplicação
│   │   ├── config_page.dart
│   │   ├── dashboard_page.dart
│   │   ├── main_window.dart
│   │   ├── playground_page.dart
│   │   └── pages.dart    # Barrel file
│   ├── widgets/          # Widgets específicos da apresentação
│   │   ├── connection_status_widget.dart
│   │   └── widgets.dart  # Barrel file
│   ├── providers/        # Gerenciamento de estado (Provider)
│   │   ├── config_provider.dart
│   │   ├── connection_provider.dart
│   │   ├── playground_provider.dart
│   │   └── providers.dart # Barrel file
│   ├── controllers/      # Controllers (quando necessário)
│   │   └── controllers.dart # Barrel file
│   ├── app/              # Configuração da aplicação
│   │   └── app.dart      # PlugAgentApp
│   └── presentation.dart # Barrel file principal
│
├── core/                  # Core Components (Compartilhado)
│   ├── constants/        # Constantes da aplicação
│   │   ├── app_constants.dart
│   │   ├── app_strings.dart
│   │   └── constants.dart # Barrel file
│   ├── di/              # Injeção de dependências (get_it)
│   │   ├── service_locator.dart
│   │   └── di.dart      # Barrel file
│   ├── extensions/       # Extensões de classes
│   │   └── extensions.dart # Barrel file
│   ├── routes/           # Rotas (go_router)
│   │   └── routes.dart  # Barrel file
│   ├── services/        # Serviços core
│   │   └── services.dart # Barrel file
│   ├── theme/           # Tema da aplicação
│   │   ├── app_colors.dart
│   │   ├── app_spacing.dart
│   │   └── theme.dart   # Barrel file
│   ├── utils/           # Utilitários
│   │   └── utils.dart   # Barrel file
│   ├── validation/      # Validação (zard)
│   │   ├── schemas/     # Schemas de validação
│   │   │   └── schemas.dart # Barrel file
│   │   └── validation.dart # Barrel file
│   ├── logger/          # Sistema de logging
│   │   ├── app_logger.dart
│   │   └── logger.dart  # Barrel file
│   └── core.dart        # Barrel file principal
│
├── shared/               # Componentes Compartilhados
│   ├── widgets/         # Widgets reutilizáveis
│   │   ├── common/     # Widgets comuns
│   │   │   ├── action_button.dart
│   │   │   ├── app_button.dart
│   │   │   ├── app_card.dart
│   │   │   ├── app_dropdown.dart
│   │   │   ├── app_text_field.dart
│   │   │   ├── cancel_button.dart
│   │   │   ├── centered_message.dart
│   │   │   ├── config_list_item.dart
│   │   │   ├── constrained_dialog.dart
│   │   │   ├── empty_state.dart
│   │   │   ├── error_widget.dart
│   │   │   ├── filter_button.dart
│   │   │   ├── loading_indicator.dart
│   │   │   ├── message_modal.dart
│   │   │   ├── numeric_field.dart
│   │   │   ├── password_field.dart
│   │   │   ├── save_button.dart
│   │   │   └── common.dart # Barrel file
│   │   ├── dashboard/  # Widgets do dashboard
│   │   │   └── dashboard.dart # Barrel file
│   │   ├── sql/       # Widgets do Playground SQL
│   │   │   ├── sql_editor.dart
│   │   │   ├── sql_action_bar.dart
│   │   │   ├── query_results_section.dart
│   │   │   ├── query_result_data_grid.dart
│   │   │   └── sql_visual_identity.dart
│   │   └── widgets.dart # Barrel file
│   ├── utils/          # Utilitários compartilhados
│   │   └── utils.dart  # Barrel file
│   ├── components/     # Componentes compartilhados
│   │   └── components.dart # Barrel file
│   └── shared.dart     # Barrel file principal
│
└── main.dart           # Ponto de entrada da aplicação
```

## 📋 Barrel Files

Barrel files (arquivos `.dart` que exportam múltiplos módulos) foram criados em cada pasta para facilitar os imports:

- **Camadas principais**: `domain.dart`, `application.dart`, `infrastructure.dart`, `presentation.dart`, `core.dart`, `shared.dart`
- **Subpastas**: Cada subpasta tem seu próprio barrel file (ex: `entities.dart`, `services.dart`, etc.)

### Uso dos Barrel Files

```dart
// ✅ Bom: Usar barrel files
import 'package:domain/domain.dart';
import 'package:application/application.dart';
import 'package:core/core.dart';

// ❌ Evitar: Imports diretos de arquivos específicos
import 'package:domain/entities/config.dart';
import 'package:domain/entities/query_request.dart';
```

## 🎯 Regras de Importação

### Domain Layer

- ✅ Pode importar: `core`, `shared`
- ❌ NÃO pode importar: `application`, `infrastructure`, `presentation`, Flutter, HTTP

### Application Layer

- ✅ Pode importar: `domain`, `core`, `shared`
- ❌ NÃO pode importar: `infrastructure`, `presentation`

### Infrastructure Layer

- ✅ Pode importar: `domain`, `core`, `shared`
- ❌ NÃO pode importar: `application`, `presentation`

### Presentation Layer

- ✅ Pode importar: `domain`, `application`, `core`, `shared`
- ❌ NÃO pode importar: `infrastructure`

## 📝 Convenções de Nomenclatura

- **Arquivos**: `snake_case.dart`
- **Classes**: `PascalCase`
- **Interfaces**: `I` + `PascalCase` (ex: `IAgentConfigRepository`)
- **Barrel Files**: Nome da pasta + `.dart` (ex: `entities.dart`, `services.dart`)

## ✅ Checklist de Estrutura

- [x] Todas as pastas principais criadas
- [x] Barrel files criados em todas as camadas
- [x] Estrutura de pastas conforme Clean Architecture
- [x] Separação clara entre camadas
- [x] Componentes compartilhados organizados
- [x] Tema e cores padronizados em `core/theme/`
