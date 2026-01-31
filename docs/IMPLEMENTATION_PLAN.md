# Plano de Implementação - Melhorias do Projeto

**Data**: 30/01/2026
**Projeto**: Plug Agente - Database Agent Windows Desktop
**Status**: Planejamento

---

## Visão Geral

Este plano implementa as melhorias identificadas na análise em **4 fases**, totalizando **~92 horas** de trabalho estimado.

### Estrutura das Fases

| Fase       | Nome                      | Horas | Impacto    | Dependências |
| ---------- | ------------------------- | ----- | ---------- | ------------ |
| **Fase 1** | Quick Wins & Estabilidade | 8h    | Alto       | Nenhuma      |
| **Fase 2** | Performance & Segurança   | 24h   | Muito Alto | Fase 1       |
| **Fase 3** | Arquitetura & Qualidade   | 32h   | Alto       | Fase 1       |
| **Fase 4** | Testes & Polimento        | 28h   | Médio      | Fase 2,3     |

**Total**: ~92 horas (aprox. 12 dias úteis de trabalho focado)

---

## FASE 1: Quick Wins & Estabilidade (8 horas)

**Objetivo**: Corrigir problemas críticos rapidamente e preparar terreno para melhorias maiores.

### 1.1 Limpeza de Dependências (30 min)

**Tarefa 1.1.1**: Remover connect_database do pubspec.yaml

- **Arquivo**: `pubspec.yaml`
- **Linha**: 48
- **Ação**: Remover linha `connect_database: ^1.0.0`
- **Validação**: `flutter pub get` executar sem erros
- **Tempo**: 5 min

```yaml
# Remover esta linha:
dependencies:
  connect_database: ^1.0.0 # ❌ Remover
```

**Tarefa 1.1.2**: Remover gzip_compressor_fixed.dart duplicado

- **Arquivo**: `lib/infrastructure/compression/gzip_compressor_fixed.dart`
- **Ação**: Excluir arquivo (é duplicata de gzip_compressor.dart)
- **Atualizar imports**: Verificar se algo importa o arquivo removido
- **Tempo**: 10 min

**Tarefa 1.1.3**: Executar flutter clean e pub get

- **Ação**: Limpar cache e rebaixar dependências
- **Comando**:
  ```bash
  flutter clean
  flutter pub get
  flutter analyze
  ```
- **Tempo**: 15 min

---

### 1.2 Corrigir throw Exception (30 min)

**Tarefa 1.2.1**: Modificar \_ensureInitialized para retornar Result

- **Arquivo**: `lib/infrastructure/external_services/odbc_database_gateway.dart`
- **Método**: `_ensureInitialized()` (linhas 30-38)
- **Problema**: Atualmente lança Exception, quebrando Result pattern

```dart
// Antes:
Future<void> _ensureInitialized() async {
  if (!_initialized) {
    final initResult = await _service.initialize();
    initResult.fold(
      (_) => _initialized = true,
      (error) => throw Exception('Failed to initialize ODBC: $error'), // ❌
    );
  }
}

// Depois:
Future<Result<Unit>> _ensureInitialized() async {
  if (_initialized) return const Success(unit);

  final initResult = await _service.initialize();
  return initResult.fold(
    (_) {
      _initialized = true;
      return const Success(unit);
    },
    (error) => Failure(
      domain.ConnectionFailure('Failed to initialize ODBC: ${_odbcErrorMessage(error)}'),
    ),
  );
}
```

**Tarefa 1.2.2**: Atualizar chamadas de \_ensureInitialized

- **Locais**: `testConnection()`, `executeQuery()`, `executeNonQuery()`
- **Ação**: Adicionar `await` e tratar Result em cada chamada

```dart
// Antes:
await _ensureInitialized();

// Depois:
final initResult = await _ensureInitialized();
if (initResult.isFailure()) {
  return Failure(initResult.exceptionOrNull()!);
}
```

**Tempo**: 30 min

---

### 1.3 Extrair Métodos de Criação de Response (30 min)

**Tarefa 1.3.1**: Criar método \_createSuccessResponse

- **Arquivo**: `lib/infrastructure/external_services/odbc_database_gateway.dart`
- **Ação**: Extrair lógica de criação de response de sucesso

```dart
QueryResponse _createSuccessResponse(QueryRequest request, QueryResult result) {
  return QueryResponse(
    id: _uuid.v4(),
    requestId: request.id,
    agentId: request.agentId,
    data: _convertQueryResultToMaps(result),
    affectedRows: result.rowCount,
    timestamp: DateTime.now(),
  );
}
```

**Tarefa 1.3.2**: Criar método \_createErrorResponse

- **Ação**: Extrair lógica de criação de response de erro

```dart
QueryResponse _createErrorResponse(QueryRequest request, String error) {
  return QueryResponse(
    id: _uuid.v4(),
    requestId: request.id,
    agentId: request.agentId,
    data: [],
    timestamp: DateTime.now(),
    error: error,
  );
}
```

**Tarefa 1.3.3**: Substituir usos duplicados

- **Locais**: Linhas 116-125, 129-138, 142-151
- **Ação**: Usar os novos métodos auxiliares

**Tempo**: 30 min

---

### 1.4 Adicionar Mounted Checks (2 horas)

**Tarefa 1.4.1**: Auditar todos os StatefulWidget

- **Ação**: Encontrar todos os async callbacks que chamam setState
- **Ferramenta**: Buscar por `setState(` após blocos `async`/`await`

**Tarefa 1.4.2**: Adicionar checks em PlaygroundProvider

- **Arquivo**: `lib/presentation/providers/playground_provider.dart`
- **Locais**: Todos os métodos async que chamam notifyListeners

```dart
// Adicionar no início de cada método async que modifica estado:
void _executeQuery() async {
  // ... código

  if (!mounted) return; // ✅ Adicionar antes de notifyListeners

  setState(() { ... });
}
```

**Tarefa 1.4.3**: Adicionar checks em PlaygroundPage

- **Arquivo**: `lib/presentation/pages/playground_page.dart`
- **Locais**: Callbacks async, especially após futures

**Tarefa 1.4.4**: Adicionar checks em ConfigPage

- **Arquivo**: `lib/presentation/pages/config_page.dart`
- **Locais**: Async callbacks após diálogos/validações

**Tarefa 1.4.5**: Verificar demais Providers e Pages

- **Arquivos**: Todos os arquivos em `lib/presentation/`

**Tempo**: 2 horas

---

### 1.5 Criar Constantes de Spacing (1 hora)

**Tarefa 1.5.1**: Criar arquivo de constantes

- **Novo arquivo**: `lib/core/theme/app_spacing.dart`
- **Conteúdo**:

```dart
/// Constantes de espaçamento para UI consistente
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;
}

/// Constantes de borda arredondada
class AppRadius {
  AppRadius._();

  static const double sm = 4.0;
  static const double md = 8.0;
  static const double lg = 12.0;
  static const double xl = 16.0;
}
```

**Tarefa 1.5.2**: Substituir hardcoded spacing em widgets (batch 1)

- **Arquivos**: `lib/shared/widgets/common/*`
- **Substituir**:
  - `EdgeInsets.all(16)` → `EdgeInsets.all(AppSpacing.md)`
  - `SizedBox(width: 8)` → `SizedBox(width: AppSpacing.sm)`
  - `SizedBox(height: 16)` → `SizedBox(height: AppSpacing.md)`

**Tarefa 1.5.3**: Substituir em presentation widgets (batch 2)

- **Arquivos**: `lib/presentation/widgets/*`
- **Mesma substituição**

**Tarefa 1.5.4**: Substituir em pages (batch 3)

- **Arquivos**: `lib/presentation/pages/*`
- **Mesma substituição**

**Tempo**: 1 hora

---

### 1.6 Adicionar Const Constructors (2 horas)

**Tarefa 1.6.1**: Adicionar const a StatelessWidget simples

- **Padrão**: Widgets sem parâmetros ou apenas parâmetros final
- **Exemplo**:

```dart
// Antes:
class MyWidget extends StatelessWidget {
  MyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('Hello');
  }
}

// Depois:
class MyWidget extends StatelessWidget {
  const MyWidget({super.key}); // ✅ Adicionar const

  @override
  Widget build(BuildContext context) {
    return const Text('Hello'); // ✅ Adicionar const
  }
}
```

**Tarefa 1.6.2**: Adicionar const em widgets filhos

- **Estratégia**: Usar const para Text, Icon, SizedBox, Padding onde possível

**Tempo**: 2 horas

---

### 1.7 Fechar StreamController (30 min)

**Tarefa 1.7.1**: Adicionar dispose method em SocketIOTransportClient

- **Arquivo**: `lib/infrastructure/external_services/socket_io_transport_client.dart`
- **Ação**: Implementar dispose para fechar streams

```dart
class SocketIOTransportClient implements ITransportClient {
  StreamController<Map<String, dynamic>>? _queryController;

  @override
  void dispose() {
    _queryController?.close();
    _queryController = null;
  }
}
```

**Tarefa 1.7.2**: Chamar dispose quando apropriado

- **Locais**: Verificar onde SocketIOTransportClient é instanciado
- **Ação**: Garantir que dispose seja chamado no ciclo de vida da aplicação

**Tempo**: 30 min

---

### 1.8 Testar e Validar (30 min)

**Tarefa 1.8.1**: Executar flutter analyze

```bash
flutter analyze --no-pub
```

**Tarefa 1.8.2**: Executar testes existentes

```bash
flutter test
```

**Tarefa 1.8.3**: Testar manualmente

- Abrir aplicação
- Testar Playground com query simples
- Testar configuração de conexão
- Verificar não há crashes

**Tempo**: 30 min

---

## FASE 2: Performance & Segurança (24 horas)

**Objetivo**: Implementar features de alta performance do odbc_fast e melhorar segurança.

### 2.1 Connection Pooling (6 horas)

**Tarefa 2.1.1**: Criar interface de pool

- **Novo arquivo**: `lib/domain/repositories/i_connection_pool.dart`
- **Conteúdo**:

```dart
import 'package:result_dart/result_dart.dart';

/// Interface para pool de conexões ODBC
abstract class IConnectionPool {
  Future<Result<String>> acquire(String connectionString);
  Future<Result<void>> release(String connectionId);
  Future<Result<void>> closeAll();
  Future<Result<int>> getActiveCount();
}
```

**Tempo**: 15 min

**Tarefa 2.1.2**: Criar implementação do pool

- **Novo arquivo**: `lib/infrastructure/pool/odbc_connection_pool.dart`
- **Conteúdo**:

```dart
import 'package:odbc_fast/odbc_fast.dart';
import 'package:result_dart/result_dart.dart';
import '../../domain/repositories/i_connection_pool.dart';
import '../../domain/errors/failures.dart' as domain;

/// Pool de conexões ODBC reutilizáveis
class OdbcConnectionPool implements IConnectionPool {
  final OdbcService _service;
  final Map<String, String> _pool = {}; // connectionString -> connectionId
  final Map<String, int> _refCount = {}; // connectionId -> count

  OdbcConnectionPool(this._service);

  @override
  Future<Result<String>> acquire(String connectionString) async {
    // Reutilizar conexão existente
    if (_pool.containsKey(connectionString)) {
      final connId = _pool[connectionString]!;
      _refCount[connId] = (_refCount[connId] ?? 0) + 1;
      return Success(connId);
    }

    // Criar nova conexão
    final result = await _service.connect(connectionString);
    return result.fold(
      (conn) {
        _pool[connectionString] = conn.id;
        _refCount[conn.id] = 1;
        return Success(conn.id);
      },
      (error) => Failure(
        domain.ConnectionFailure('Failed to create connection: ${error.message}'),
      ),
    );
  }

  @override
  Future<Result<void>> release(String connectionId) async {
    if (!_refCount.containsKey(connectionId)) {
      return Failure(
        domain.ConnectionFailure('Connection not found in pool: $connectionId'),
      );
    }

    _refCount[connectionId] = _refCount[connectionId]! - 1;

    // Manter conexão viva para reuso (não desconectar)
    return const Success(unit);
  }

  @override
  Future<Result<void>> closeAll() async {
    final errors = <String>[];

    for (final connId in _pool.values) {
      final result = await _service.disconnect(connId);
      result.fold(
        (_) {},
        (error) => errors.add(error.message),
      );
    }

    _pool.clear();
    _refCount.clear();

    if (errors.isNotEmpty) {
      return Failure(
        domain.ConnectionFailure('Errors closing pool: ${errors.join(', ')}'),
      );
    }
    return const Success(unit);
  }

  @override
  Future<Result<int>> getActiveCount() async {
    return Success(_pool.length);
  }
}
```

**Tempo**: 2 horas

**Tarefa 2.1.3**: Integrar pool no OdbcDatabaseGateway

- **Arquivo**: `lib/infrastructure/external_services/odbc_database_gateway.dart`
- **Modificações**:

```dart
class OdbcDatabaseGateway implements IDatabaseGateway {
  final OdbcService _service;
  final IAgentConfigRepository _configRepository;
  final IConnectionPool _connectionPool; // ✅ Adicionar
  final Uuid _uuid;

  OdbcDatabaseGateway(
    this._configRepository,
    this._service,
    this._connectionPool, // ✅ Adicionar parâmetro
  ) : _uuid = const Uuid();

  // Modificar executeQuery para usar pool:
  @override
  Future<Result<QueryResponse>> executeQuery(QueryRequest request) async {
    await _ensureInitialized();

    final configResult = await _configRepository.getCurrentConfig();

    return configResult.fold(
      (config) async {
        final connectionString = OdbcConnectionBuilder.build(localConfig);

        // ✅ Usar pool ao invés de connect direto
        final poolResult = await _connectionPool.acquire(connectionString);

        return poolResult.fold(
          (connId) async {
            final result = await _service.executeQuery(connId, request.query);

            // ✅ Release de volta ao pool (não desconectar)
            await _connectionPool.release(connId);

            return result.fold(
              (queryResult) => Success(_createSuccessResponse(request, queryResult)),
              (error) => Success(_createErrorResponse(request, _odbcErrorMessage(error))),
            );
          },
          (error) => Success(_createErrorResponse(request, _odbcErrorMessage(error))),
        );
      },
      (failure) => Success(_createErrorResponse(request, failure.toString())),
    );
  }
}
```

**Tempo**: 1.5 horas

**Tarefa 2.1.4**: Registrar pool no service_locator

- **Arquivo**: `lib/core/di/service_locator.dart`
- **Adicionar**:

```dart
// Connection Pool
getIt.registerLazySingleton<IConnectionPool>(() => OdbcConnectionPool(getIt<OdbcService>()));

// Atualizar OdbcDatabaseGateway:
getIt.registerLazySingleton<IDatabaseGateway>(
  () => OdbcDatabaseGateway(
    getIt<IAgentConfigRepository>(),
    getIt<OdbcService>(),
    getIt<IConnectionPool>(), // ✅ Adicionar pool
  ),
);
```

**Tempo**: 15 min

**Tarefa 2.1.5**: Testar pool

- Criar teste unitário
- Testar com múltiplas queries simultâneas
- Verificar reuso de conexão

**Tempo**: 1.5 horas

---

### 2.2 Streaming para Queries Grandes (8 horas)

**Tarefa 2.2.1**: Criar interface de streaming

- **Novo arquivo**: `lib/domain/repositories/i_streaming_database_gateway.dart`
- **Conteúdo**:

```dart
import 'package:result_dart/result_dart.dart';

abstract class IStreamingDatabaseGateway {
  /// Executa query em streaming, processando em chunks
  Future<Result<void>> executeQueryStream(
    String query,
    String connectionString,
    void Function(List<Map<String, dynamic>> chunk) onChunk, {
    int fetchSize = 1000,
    int chunkSizeBytes = 1024 * 1024,
  });
}
```

**Tempo**: 15 min

**Tarefa 2.2.2**: Criar implementação de streaming

- **Novo arquivo**: `lib/infrastructure/external_services/odbc_streaming_gateway.dart`
- **Conteúdo**:

```dart
import 'package:odbc_fast/odbc_fast.dart';
import 'package:result_dart/result_dart.dart';
import '../../domain/repositories/i_streaming_database_gateway.dart';

/// Gateway com suporte a streaming para grandes datasets
class OdbcStreamingGateway implements IStreamingDatabaseGateway {
  final AsyncNativeOdbcConnection _connection;

  OdbcStreamingGateway() : _connection = AsyncNativeOdbcConnection();

  Future<void> _ensureInitialized() async {
    if (!_connection.isInitialized) {
      await _connection.initialize();
    }
  }

  @override
  Future<Result<void>> executeQueryStream(
    String query,
    String connectionString,
    void Function(List<Map<String, dynamic>> chunk) onChunk, {
    int fetchSize = 1000,
    int chunkSizeBytes = 1024 * 1024,
  }) async {
    await _ensureInitialized();

    final connId = await _connection.connect(connectionString);

    try {
      await for (final chunk in _connection.streamQueryBatched(
        connId,
        query,
        fetchSize: fetchSize,
        chunkSize: chunkSizeBytes,
      )) {
        final rows = _convertChunkToMaps(chunk);
        onChunk(rows);
      }

      await _connection.disconnect(connId);
      return const Success(unit);
    } catch (e) {
      await _connection.disconnect(connId);
      return Failure(StreamingQueryException('Stream error: $e'));
    }
  }

  List<Map<String, dynamic>> _convertChunkToMaps(dynamic chunk) {
    // Implementar conversão
    final rows = <Map<String, dynamic>>[];
    // ... lógica de conversão
    return rows;
  }
}
```

**Tempo**: 3 horas

**Tarefa 2.2.3**: Criar use case de streaming

- **Novo arquivo**: `lib/application/use_cases/execute_streaming_query.dart`
- **Conteúdo**:

```dart
import 'package:result_dart/result_dart.dart';
import '../../domain/repositories/i_streaming_database_gateway.dart';

class ExecuteStreamingQuery {
  final IStreamingDatabaseGateway _gateway;

  ExecuteStreamingQuery(this._gateway);

  Future<Result<void>> call(
    String query,
    String connectionString,
    void Function(List<Map<String, dynamic>>) onChunk,
  ) async {
    if (query.trim().isEmpty) {
      return Failure(ValidationFailure('Query cannot be empty'));
    }

    return await _gateway.executeQueryStream(query, connectionString, onChunk);
  }
}
```

**Tempo**: 30 min

**Tarefa 2.2.4**: Integrar streaming no PlaygroundProvider

- **Arquivo**: `lib/presentation/providers/playground_provider.dart`
- **Adicionar**:

```dart
class PlaygroundProvider extends ChangeNotifier {
  final IStreamingDatabaseGateway _streamingGateway;

  // Nova propriedade para rastreamento progresso
  bool _isStreaming = false;
  int _rowsProcessed = 0;
  double _progress = 0.0;

  bool get isStreaming => _isStreaming;
  int get rowsProcessed => _rowsProcessed;
  double get progress => _progress;

  // Método para executar com streaming
  Future<void> executeQueryWithStreaming(String query) async {
    _isLoading = true;
    _isStreaming = true;
    _rowsProcessed = 0;
    _results = [];
    notifyListeners();

    try {
      final config = await _configRepository.getCurrentConfig();
      final connStr = OdbcConnectionBuilder.build(config.toDatabaseConfig());

      await _streamingGateway.executeQueryStream(
        query,
        connStr,
        (chunk) {
          // Callback a cada chunk
          _results.addAll(chunk);
          _rowsProcessed += chunk.length;
          _progress = _rowsProcessed / _estimatedTotalRows;
          notifyListeners(); // ✅ UI atualiza em tempo real
        },
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      _isStreaming = false;
      notifyListeners();
    }
  }
}
```

**Tempo**: 2 horas

**Tarefa 2.2.5**: Adicionar indicador de progresso na UI

- **Arquivo**: `lib/shared/widgets/sql/query_results_section.dart`
- **Adicionar widget**:

```dart
Widget _buildStreamingProgress() {
  if (!playgroundProvider.isStreaming) return const SizedBox.shrink();

  return Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          ProgressBar(value: playgroundProvider.progress),
          const SizedBox(height: AppSpacing.sm),
          Text('Processando: ${playgroundProvider.rowsProcessed} linhas'),
        ],
      ),
    ),
  );
}
```

**Tempo**: 1.5 horas

**Tarefa 2.2.6**: Testar streaming

- Criar query de teste com muitos resultados
- Verificar consumo de memória constante
- Verificar UI responsiva durante execução

**Tempo**: 1 hora

---

### 2.3 Prepared Statements (3 horas)

**Tarefa 2.3.1**: Criar validador de SQL injection

- **Novo arquivo**: `lib/application/validation/sql_validator.dart`
- **Conteúdo**:

```dart
import '../../domain/errors/failures.dart';

class SqlValidator {
  /// Valida se query contém placeholders para parâmetros
  static Result<void> validateParameterized(String query) {
    if (query.contains('\'') || query.contains('"')) {
      // Possível SQL injection com string literals
      return Failure(
        ValidationFailure(
          'Use placeholders (?) ao invés de string literals em queries',
        ),
      );
    }
    return const Success(unit);
  }

  /// Extrai parâmetros nomeados da query
  static List<String> extractNamedParameters(String query) {
    final regex = RegExp(r':(\w+)');
    return regex.allMatches(query).map((m) => m.group(1)!).toList();
  }
}
```

**Tempo**: 1 hora

**Tarefa 2.3.2**: Atualizar executeQuery para suportar parâmetros

- **Arquivo**: `lib/infrastructure/external_services/odbc_database_gateway.dart`
- **Modificação**:

```dart
@override
Future<Result<QueryResponse>> executeQuery(
  QueryRequest request, {
  Map<String, dynamic>? parameters,
}) async {
  await _ensureInitialized();

  // ✅ Validar se há parâmetros, usar prepared statement
  if (parameters != null && parameters.isNotEmpty) {
    return _executeQueryParams(request, parameters);
  }

  // Código existente sem parâmetros...
}

Future<Result<QueryResponse>> _executeQueryParams(
  QueryRequest request,
  Map<String, dynamic> params,
) async {
  final connResult = await _connectionPool.acquire(connectionString);
  // ... usar executeQueryParams do odbc_fast
}
```

**Tempo**: 1 hora

**Tarefa 2.3.3**: Criar helper de query builder

- **Novo arquivo**: `lib/application/services/query_builder_service.dart`
- **Conteúdo**:

```dart
class QueryBuilder {
  /// Cria query com parâmetros posicionais
  static String withParams(String query, List<dynamic> params) {
    final placeholders = List.filled(params.length, '?').join(', ');
    return query.replaceAll('?', placeholders);
  }

  /// Converte map de parâmetros para lista posicional
  static List<dynamic> mapToPositionalParams(
    Map<String, dynamic> params,
    List<String> paramOrder,
  ) {
    return paramOrder.map((key) => params[key]).toList();
  }
}
```

**Tempo**: 1 hora

---

### 2.4 Retry Mechanism (2 horas)

**Tarefa 2.4.1**: Criar configurador de retry

- **Novo arquivo**: `lib/core/config/retry_config.dart`
- **Conteúdo**:

```dart
import 'package:odbc_fast/odbc_fast.dart';

class RetryConfig {
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final double backoffMultiplier;

  const RetryConfig({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 100),
    this.maxDelay = const Duration(seconds: 10),
    this.backoffMultiplier = 2.0,
  });

  /// Configuração padrão para erros transitórios
  static const transient = RetryConfig(
    maxAttempts: 3,
    initialDelay: Duration(milliseconds: 100),
    maxDelay: Duration(seconds: 5),
  );

  /// Configuração para timeouts de conexão
  static const connectionTimeout = RetryConfig(
    maxAttempts: 2,
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 5),
  );
}
```

**Tempo**: 30 min

**Tarefa 2.4.2**: Implementar wrapper de retry

- **Novo arquivo**: `lib/application/services/retry_service.dart`
- **Conteúdo**:

```dart
import 'package:odbc_fast/odbc_fast.dart';
import '../../core/config/retry_config.dart';

class RetryService {
  final OdbcService _service;

  RetryService(this._service);

  Future<Result<T>> executeWithRetry<T>(
    Future<Result<T>> Function() operation,
    RetryConfig config,
  ) async {
    Result<T>? lastResult;
    Duration delay = config.initialDelay;

    for (int attempt = 0; attempt < config.maxAttempts; attempt++) {
      final result = await operation();

      if (result.isSuccess()) {
        return result;
      }

      // Verificar se erro é retryable
      final error = result.exceptionOrNull();
      if (error != null && _isRetryable(error)) {
        lastResult = result;
        await Future.delayed(delay);

        // Exponential backoff
        delay = Duration(
          microseconds: (delay.inMicroseconds * config.backoffMultiplier).clamp(
            config.initialDelay.inMicroseconds,
            config.maxDelay.inMicroseconds,
          ),
        );
        continue;
      }

      // Não é retryable, retornar falha
      return result;
    }

    return lastResult!; // Retornar última falha após todas tentativas
  }

  bool _isRetryable(Object error) {
    if (error is ConnectionError) {
      return error.isRetryable;
    }
    return false;
  }
}
```

**Tempo**: 1 hora

**Tarefa 2.4.3**: Integrar retry no OdbcDatabaseGateway

- **Arquivo**: `lib/infrastructure/external_services/odbc_database_gateway.dart`
- **Adicionar retry em operações críticas**

```dart
class OdbcDatabaseGateway implements IDatabaseGateway {
  final RetryService _retryService;

  @override
  Future<Result<bool>> testConnection(String connectionString) async {
    return await _retryService.executeWithRetry(
      () => _testConnectionInternal(connectionString),
      RetryConfig.connectionTimeout,
    );
  }
}
```

**Tempo**: 30 min

---

### 2.5 Métricas de Performance (3 horas)

**Tarefa 2.5.1**: Criar coletor de métricas

- **Novo arquivo**: `lib/application/services/metrics_service.dart`
- **Conteúdo**:

```dart
import 'package:odbc_fast/odbc_fast.dart';

class QueryMetrics {
  final int queryCount;
  final int errorCount;
  final Duration totalLatency;
  final Duration avgLatency;
  final Duration p99Latency;
  final DateTime lastUpdated;

  const QueryMetrics({
    this.queryCount = 0,
    this.errorCount = 0,
    this.totalLatency = Duration.zero,
    this.avgLatency = Duration.zero,
    this.p99Latency = Duration.zero,
    required this.lastUpdated,
  });

  QueryMetrics copyWith({
    int? queryCount,
    int? errorCount,
    Duration? totalLatency,
    Duration? avgLatency,
    Duration? p99Latency,
    DateTime? lastUpdated,
  }) {
    return QueryMetrics(
      queryCount: queryCount ?? this.queryCount,
      errorCount: errorCount ?? this.errorCount,
      totalLatency: totalLatency ?? this.totalLatency,
      avgLatency: avgLatency ?? this.avgLatency,
      p99Latency: p99Latency ?? this.p99Latency,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

class MetricsService {
  final OdbcService _odbcService;
  QueryMetrics _metrics = const QueryMetrics(lastUpdated: null);

  MetricsService(this._odbcService);

  Future<void> updateMetrics() async {
    final odbcMetrics = await _odbcService.getMetrics();
    odbcMetrics.fold(
      (m) {
        _metrics = QueryMetrics(
          queryCount: m.queryCount,
          errorCount: m.errorCount,
          totalLatency: Duration(milliseconds: m.totalLatencyMs.toInt()),
          avgLatency: Duration(milliseconds: m.avgLatencyMs.toInt()),
          p99Latency: Duration(milliseconds: m.p99LatencyMs.toInt()),
          lastUpdated: DateTime.now(),
        );
      },
      (_) {},
    );
  }

  QueryMetrics get metrics => _metrics;
}
```

**Tempo**: 1.5 horas

**Tarefa 2.5.2**: Adicionar métricas no Provider

- **Arquivo**: `lib/presentation/providers/playground_provider.dart`
- **Adicionar**:

```dart
class PlaygroundProvider extends ChangeNotifier {
  final MetricsService _metricsService;
  QueryMetrics _metrics = const QueryMetrics(lastUpdated: null);

  QueryMetrics get metrics => _metrics;

  Future<void> executeQuery(String query) async {
    final stopwatch = Stopwatch()..start();

    final result = await _gateway.executeQuery(request);

    stopwatch.stop();

    // Atualizar métricas
    await _metricsService.updateMetrics();
    _metrics = _metricsService.metrics;
    notifyListeners();
  }
}
```

**Tempo**: 1 hora

**Tarefa 2.5.3**: Criar widget de métricas

- **Novo arquivo**: `lib/shared/widgets/dashboard/metrics_card.dart`
- **Conteúdo**:

```dart
class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.metrics});

  final QueryMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Métricas ODBC', style: context.typography.titleLarge),
            const SizedBox(height: AppSpacing.md),
            _MetricRow(
              icon: Icons.query_stats,
              label: 'Queries Executadas',
              value: metrics.queryCount.toString(),
            ),
            _MetricRow(
              icon: Icons.error_outline,
              label: 'Erros',
              value: metrics.errorCount.toString(),
            ),
            _MetricRow(
              icon: Icons.schedule,
              label: 'Latência Média',
              value: '${metrics.avgLatency.inMilliseconds}ms',
            ),
            _MetricRow(
              icon: Icons.speed,
              label: 'Latência P99',
              value: '${metrics.p99Latency.inMilliseconds}ms',
            ),
          ],
        ),
      ),
    );
  }
}
```

**Tempo**: 30 min

---

### 2.6 Testar Fase 2 (2 horas)

**Tarefa 2.6.1**: Testar connection pool

- Criar múltiplas queries simultâneas
- Verificar reuso de conexão
- Testar release de conexões

**Tarefa 2.6.2**: Testar streaming

- Criar query com >100k linhas
- Verificar consumo de memória
- Testar responsividade da UI

**Tarefa 2.6.3**: Testar retry mechanism

- Simular falhas de rede
- Verificar tentativas de retry

**Tarefa 2.6.4**: Validar performance

- Comparar antes/depois
- Medir latência de queries

**Tempo**: 2 horas

---

## FASE 3: Arquitetura & Qualidade (32 horas)

**Objetivo**: Corrigir violações de arquitetura e melhorar qualidade do código.

### 3.1 Criar Interfaces para Serviços (4 horas)

**Tarefa 3.1.1**: Criar ICompressor

- **Arquivo**: `lib/domain/repositories/i_compressor.dart`
- **Interface**:

```dart
import 'package:result_dart/result_dart.dart';

abstract class ICompressor {
  Future<Result<List<Map<String, dynamic>>>> compress(
    List<Map<String, dynamic>> data,
  );

  Future<Result<List<Map<String, dynamic>>>> decompress(
    List<Map<String, dynamic>> data,
  );
}
```

**Tempo**: 15 min

**Tarefa 3.1.2**: Criar IQueryNormalizer

- **Arquivo**: `lib/domain/services/i_query_normalizer.dart`
- **Interface**:

```dart
import 'package:result_dart/result_dart.dart';
import '../entities/query_response.dart';

abstract class IQueryNormalizer {
  Future<Result<QueryResponse>> normalize(QueryResponse response);
}
```

**Tempo**: 15 min

**Tarefa 3.1.3**: Atualizar CompressionService

- **Arquivo**: `lib/application/services/compression_service.dart`
- **Modificar**: Usar ICompressor ao invés de implementação concreta

**Tempo**: 30 min

**Tarefa 3.1.4**: Atualizar QueryNormalizerService

- **Arquivo**: `lib/application/services/query_normalizer_service.dart`
- **Modificar**: Usar IQueryNormalizer

**Tempo**: 30 min

**Tarefa 3.1.5**: Atualizar service_locator

- **Arquivo**: `lib/core/di/service_locator.dart`
- **Registrar**: Interfaces com implementações

**Tempo**: 30 min

---

### 3.2 Corrigir Violações de Import (3 horas)

**Tarefa 3.2.1**: Remover imports de Infrastructure no Application

- **Arquivos**:
  - `lib/application/services/compression_service.dart`
  - `lib/application/services/query_normalizer_service.dart`
- **Ação**: Usar interfaces do Domain

**Tempo**: 1 hora

**Tarefa 3.2.2**: Mover DI setup para Infrastructure

- **Ação**: Criar `lib/infrastructure/di/infrastructure_di.dart`
- **Conteúdo**: Setup de dependências de infrastructure

```dart
import 'package:get_it/get_it.dart';
import '../../domain/repositories/...';

void setupInfrastructureDependencies(GetIt getIt) {
  getIt.registerLazySingleton<ICompressor>(() => GzipCompressor());
  // ... outros
}
```

**Tempo**: 1.5 horas

**Tarefa 3.2.3**: Atualizar main.dart

- **Ação**: Chamar setup de cada camada em ordem correta

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final getIt = GetIt.instance;

  // 1. Core/Shared
  setupCoreDependencies(getIt);

  // 2. Infrastructure
  setupInfrastructureDependencies(getIt);

  // 3. Application
  setupApplicationDependencies(getIt);

  // 4. Presentation
  setupPresentationDependencies(getIt);

  runApp(MyApp());
}
```

**Tempo**: 30 min

---

### 3.3 Refatorar Métodos Longos (8 horas)

**Tarefa 3.3.1**: Extrair lógica de connection em OdbcDatabaseGateway

- **Arquivo**: `lib/infrastructure/external_services/odbc_database_gateway.dart`
- **Método auxiliar**:

```dart
Future<Result<T>> _withConnection<T>(
  DatabaseConfig config,
  Future<Result<T>> Function(String connectionId) operation,
) async {
  final connStr = OdbcConnectionBuilder.build(config);

  final connResult = await _connectionPool.acquire(connStr);

  return connResult.fold(
    (connId) async {
      final result = await operation(connId);
      await _connectionPool.release(connId);
      return result;
    },
    (error) => Failure(...),
  );
}
```

**Tempo**: 2 horas

**Tarefa 3.3.2**: Simplificar executeQuery

- **Ação**: Usar `_withConnection` helper
- **Resultado**: Reduzir de 77 para ~30 linhas

**Tempo**: 1 hora

**Tarefa 3.3.3**: Simplificar executeNonQuery

- **Ação**: Usar `_withConnection` helper
- **Resultado**: Reduzir de 45 para ~20 linhas

**Tempo**: 1 hora

**Tarefa 3.3.4**: Refatorar socket_io_transport_client

- **Arquivo**: `lib/infrastructure/external_services/socket_io_transport_client.dart`
- **Ação**: Extrair event handlers para métodos separados

```dart
// Antes:
void connect(...) {
  socket.on('query', (data) { /* 50 linhas */ });
  socket.on('error', (error) { /* 30 linhas */ });
}

// Depois:
void connect(...) {
  socket.on('query', _handleQuery);
  socket.on('error', _handleError);
}

void _handleQuery(dynamic data) { /* ... */ }
void _handleError(dynamic error) { /* ... */ }
```

**Tempo**: 3 horas

**Tarefa 3.3.5**: Refatorar handle_query_request

- **Arquivo**: `lib/application/use_cases/handle_query_request.dart`
- **Ação**: Extrair lógica de compressão/normalização

**Tempo**: 1 hora

---

### 3.4 Melhorar Error Handling (4 horas)

**Tarefa 3.4.1**: Adicionar tipos específicos de exceção

- **Arquivo**: `lib/domain/errors/failures.dart`
- **Adicionar**:

```dart
class ConnectionInitializationFailure extends Failure {
  ConnectionInitializationFailure(super.message);
}

class StreamingQueryException extends Failure {
  StreamingQueryException(super.message);
}

class PoolExhaustedException extends Failure {
  PoolExhaustedException(super.message);
}
```

**Tempo**: 30 min

**Tarefa 3.4.2**: Substituir catch genéricos

- **Arquivos**: Múltiplos arquivos com `catch (e)`
- **Ação**: Especificar tipos de exceção

```dart
// Antes:
try { ... } catch (e) { ... }

// Depois:
try { ... }
on SocketException catch (e) {
  return Failure(NetworkFailure('Socket error: ${e.message}'));
} on OdbcException catch (e) {
  return Failure(DatabaseFailure('ODBC error: ${e.message}'));
} catch (e) {
  return Failure(UnknownFailure('Unexpected error: $e'));
}
```

**Tempo**: 2 horas

**Tarefa 3.4.3**: Adicionar logging estruturado

- **Arquivos**: Pontos críticos de erro
- **Ação**: Usar `dart:developer` log

```dart
import 'dart:developer' as developer;

try {
  await operation();
} catch (e, s) {
  developer.log(
    'Operation failed',
    name: 'odbc_gateway',
    error: e,
    stackTrace: s,
    level: 1000, // SEVERE
  );
  rethrow;
}
```

**Tempo**: 1.5 horas

---

### 3.5 Criar Constants para Strings (2 horas)

**Tarefa 3.5.1**: Criar arquivo de constantes de UI

- **Novo arquivo**: `lib/core/constants/ui_strings.dart`
- **Conteúdo**:

```dart
class AppStrings {
  AppStrings._();

  // Common
  static const String execute = 'Executar';
  static const String testConnection = 'Testar Conexão';
  static const String clear = 'Limpar';
  static const String save = 'Salvar';
  static const String cancel = 'Cancelar';

  // Messages
  static const String noResults = 'Nenhum resultado encontrado';
  static const String querySuccess = 'Query executada com sucesso';
  static const String queryError = 'Erro ao executar query';

  // Placeholders
  static String resultsCount(int count) => '$count resultados encontrados';
  static String executionTime(Duration d) => 'Tempo: ${d.inSeconds}s';
}
```

**Tempo**: 30 min

**Tarefa 3.5.2**: Substituir strings hardcoded

- **Arquivos**: Arquivos de UI em `lib/presentation/` e `lib/shared/widgets/`
- **Ação**: Usar AppStrings

**Tempo**: 1.5 horas

---

### 3.6 Melhorar Análise de Código (6 horas)

**Tarefa 3.6.1**: Executar flutter analyze com regras estritas

- **Comando**: `flutter analyze --fatal-infos --fatal-warnings`
- **Ação**: Corrigir todos os warnings

**Tempo**: 1 hora

**Tarefa 3.6.2**: Executar dart fix

- **Comando**: `dart fix --apply`
- **Ação**: Aplicar correções automáticas

**Tempo**: 30 min

**Tarefa 3.6.3**: Executar very good analysis

- **Comando**: Ativar `very_good_analysis` no analysis_options.yaml
- **Ação**: Corrigir novas violações

**Tempo**: 2 horas

**Tarefa 3.6.4**: Adiciona mais regras customizadas

- **Arquivo**: `analysis_options.yaml`
- **Regras**: Adicionar regras para:
  - Tamanho máximo de função (20 linhas)
  - Tamanho máximo de arquivo (300 linhas)
  - Complexidade ciclomática

**Tempo**: 2 horas

**Tarefa 3.6.5**: Remover código morto

- **Ação**: Buscar e remover:
  - Comentários antigos
  - Funções não utilizadas
  - Imports não utilizados

**Tempo**: 30 min

---

### 3.7 Adicionar Suporte a Cancelamento (5 horas)

**Tarefa 3.7.1**: Criar CancellationToken

- **Novo arquivo**: `lib/core/utils/cancellation_token.dart`
- **Conteúdo**:

```dart
class CancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw OperationCancelledException();
    }
  }
}
```

**Tempo**: 30 min

**Tarefa 3.7.2**: Integrar cancelamento em queries longas

- **Arquivo**: `lib/presentation/providers/playground_provider.dart`
- **Adicionar**:

```dart
class PlaygroundProvider extends ChangeNotifier {
  CancellationToken? _cancelToken;

  Future<void> executeQuery(String query) async {
    _cancelToken = CancellationToken();

    try {
      // Passar token para gateway
      final result = await _gateway.executeQuery(
        request,
        cancelToken: _cancelToken,
      );
    } on OperationCancelledException {
      // Query foi cancelada
    }
  }

  void cancelQuery() {
    _cancelToken?.cancel();
  }
}
```

**Tempo**: 2 horas

**Tarefa 3.7.3**: Adicionar botão de cancelar na UI

- **Arquivo**: `lib/presentation/pages/playground_page.dart`
- **Ação**: Mostrar botão "Cancelar" durante execução

```dart
SqlActionBar(
  onExecute: _executeQuery,
  onCancel: _isExecuting ? _cancelQuery : null,
  isExecuting: _isExecuting,
)
```

**Tempo**: 1.5 horas

**Tarefa 3.7.4**: Testar cancelamento

- Testar cancelamento durante query longa
- Verificar limpeza de recursos

**Tempo**: 1 hora

---

## FASE 4: Testes & Polimento (28 horas)

**Objetivo**: Adicionar cobertura de testes e melhorias finais de UX.

### 4.1 Testes Unitários (12 horas)

**Tarefa 4.1.1**: Testar OdbcDatabaseGateway

- **Novo arquivo**: `test/infrastructure/external_services/odbc_database_gateway_test.dart`
- **Test cases**:
  - ✅ Conexão com sucesso
  - ✅ Conexão com erro
  - ✅ Query com resultados
  - ✅ Query vazia
  - ✅ Query com erro
  - ✅ NonQuery com affected rows
  - ✅ Cleanup de conexão

```dart
group('OdbcDatabaseGateway', () {
  late OdbcDatabaseGateway gateway;
  late MockOdbcService mockService;
  late MockAgentConfigRepository mockConfigRepo;

  setUp(() {
    mockService = MockOdbcService();
    mockConfigRepo = MockAgentConfigRepository();
    gateway = OdbcDatabaseGateway(mockConfigRepo, mockService);
  });

  test('deve conectar com sucesso', () async {
    // Arrange
    final mockConnection = MockConnection();
    when(() => mockService.connect(any())).thenReturn(Success(mockConnection));
    when(() => mockService.disconnect(any())).thenReturn(Success(unit));

    // Act
    final result = await gateway.testConnection('DSN=test');

    // Assert
    expect(result.isSuccess(), true);
    expect(result.getOrNull(), true);
  });

  test('deve executar query e retornar dados', () async {
    // Arrange
    final mockQueryResult = QueryResult(
      columns: ['id', 'name'],
      rows: [[1, 'Alice'], [2, 'Bob']],
      rowCount: 2,
    );

    // Act & Assert
    // ... implementação
  });

  test('deve retornar erro ao falhar conexão', () async {
    // ...
  });
});
```

**Tempo**: 4 horas

**Tarefa 4.1.2**: Testar Connection Pool

- **Novo arquivo**: `test/infrastructure/pool/odbc_connection_pool_test.dart`
- **Test cases**:
  - ✅ Reuso de conexão
  - ✅ Múltiplas aquisições
  - ✅ Release de conexão
  - ✅ CloseAll
  - ✅ Contagem de conexões ativas

**Tempo**: 2 horas

**Tarefa 4.1.3**: Testar Services

- **Arquivos**:
  - `test/application/services/compression_service_test.dart`
  - `test/application/services/query_normalizer_service_test.dart`
  - `test/application/services/retry_service_test.dart`
  - `test/application/services/metrics_service_test.dart`

**Tempo**: 3 horas

**Tarefa 4.1.4**: Testar Use Cases

- **Arquivos**:
  - `test/application/use_cases/execute_playground_query_test.dart`
  - `test/application/use_cases/test_db_connection_test.dart`
  - `test/application/use_cases/handle_query_request_test.dart`

**Tempo**: 3 horas

---

### 4.2 Widget Tests (8 horas)

**Tarefa 4.2.1**: Testar ConnectionStatusWidget

- **Test cases**:
  - ✅ Mostra ícone verde quando conectado
  - ✅ Mostra ícone vermelho quando desconectado
  - ✅ Mostra ícone amarelo quando conectando

**Tempo**: 1 hora

**Tarefa 4.2.2**: Testar MessageModal

- **Test cases**:
  - ✅ Renderiza título e mensagem
  - ✅ Botão OK funciona
  - ✅ Tem ícone correto por tipo

**Tempo**: 1 hora

**Tarefa 4.2.3**: Testar QueryResultsSection

- **Test cases**:
  - ✅ Mostra resultados quando há dados
  - ✅ Mostra mensagem vazia quando sem dados
  - ✅ Formata tempo corretamente

**Tempo**: 1.5 horas

**Tarefa 4.2.4**: Testar SqlEditor

- **Test cases**:
  - ✅ Atualiza texto onInput
  - ✅ Limpa texto onClear
  - ✅ Execute callback funciona

**Tempo**: 1 hora

**Tarefa 4.2.5**: Testar Pages

- **Arquivos**:
  - `test/presentation/pages/playground_page_test.dart`
  - `test/presentation/pages/config_page_test.dart`

**Tempo**: 3 horas

**Tarefa 4.2.6**: Testar Providers

- **Arquivos**:
  - `test/presentation/providers/playground_provider_test.dart`
  - `test/presentation/providers/connection_provider_test.dart`

**Tempo**: 30 min

---

### 4.3 Melhorias de UI/UX (6 horas)

**Tarefa 4.3.1**: Adicionar empty states

- **Arquivos**: Various UI files
- **Ação**: Adicionar mensagens úteis e sugestões

```dart
// Playground vazio
Widget _buildEmptyState() {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.search_off, size: 64, color: Colors.grey),
        const SizedBox(height: AppSpacing.md),
        const Text('Nenhuma query executada ainda'),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Digite uma query SQL acima e clique em Executar',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ExampleQueries(onTap: (query) => _setQuery(query)),
      ],
    ),
  );
}
```

**Tempo**: 2 horas

**Tarefa 4.3.2**: Adicionar loading indicators

- **Locais**: Operações async sem feedback visual
- **Widgets**: ProgressRing para status indeterminado

```dart
// Teste de conexão
if (_isTestingConnection) {
  return const Row(
    children: [
      ProgressRing(size: 16),
      SizedBox(width: AppSpacing.sm),
      Text('Testando conexão...'),
    ],
  );
}
```

**Tempo**: 1.5 horas

**Tarefa 4.3.3**: Melhorar feedback de erro

- **Ação**: Mensagens de erro mais específicas e acionáveis
- **Exemplo**:

```dart
// Antes:
'Erro ao conectar'

// Depois:
Card(
  child: Column(
    children: [
      Icon(Icons.error, color: Colors.red),
      Text('Falha de conexão'),
      Text('Verifique:'),
      Bullet(text: 'Driver ODBC instalado'),
      Bullet(text: 'Credenciais corretas'),
      Bullet(text: 'Servidor acessível'),
      FilledButton(
        child: Text('Tentar Novamente'),
        onPressed: _retry,
      ),
    ],
  ),
)
```

**Tempo**: 1.5 horas

**Tarefa 4.3.4**: Adicionar atalhos de teclado

- **Arquivo**: `lib/presentation/pages/playground_page.dart`
- **Atalhos**:
  - `F5`: Executar query
  - `Ctrl+Enter`: Executar query
  - `Ctrl+K`: Limpar editor
  - `Ctrl+L`: Limpar resultados
  - `Esc`: Cancelar query

```dart
Shortcuts(
  // F5 para executar
  ShortcutItem(
    character: LogicalKeyKey.f5,
    onInvoke: (_) => _executeQuery(),
  ),

  // Ctrl+Enter para executar
  ShortcutItem(
    character: LogicalKeyKey.enter,
    modifiers: {LogicalKeyKey.control},
    onInvoke: (_) => _executeQuery(),
  ),
)
```

**Tempo**: 1 hora

---

### 4.4 Localização (2 horas)

**Tarefa 4.4.1**: Configurar flutter_localizations

- **Arquivo**: `pubspec.yaml`
- **Adicionar**:

```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
```

**Tempo**: 15 min

**Tarefa 4.4.2**: Criar arquivo de localização

- **Novo arquivo**: `lib/l10n/app_localizations.dart`
- **Conteúdo**: Strings traduzíveis

**Tempo**: 1 hora

**Tarefa 4.4.3**: Integrar localização na UI

- **Ação**: Usar `AppLocalizations.of(context)!.xxx`

**Tempo**: 45 min

---

## Cronograma de Implementação

### Semana 1: Fase 1 - Quick Wins

```
Dia 1 (4h): Limpeza, throw Exception, mounted checks
Dia 2 (4h): Constantes, const constructors, StreamController, testes
```

### Semana 2: Fase 2 - Performance

```
Dia 1 (6h): Connection Pool
Dia 2 (8h): Streaming
Dia 3 (6h): Prepared Statements + Retry
Dia 4 (4h): Métricas + Testes
```

### Semana 3: Fase 3 - Arquitetura

```
Dia 1 (4h): Interfaces (ICompressor, etc.)
Dia 2 (3h): Corrigir imports + DI
Dia 3 (8h): Refatorar métodos longos
Dia 4 (6h): Error handling + consts
Dia 5 (6h): Análise de código + cancelamento
```

### Semana 4: Fase 4 - Testes & Polimento

```
Dia 1 (8h): Testes unitários (ODBC, Pool, Services)
Dia 2 (8h): Widget tests
Dia 3 (6h): Melhorias UI/UX
Dia 4 (4h): Localização
Dia 5 (2h): Testes finais + documentação
```

---

## Checklist de Validação

### Pré-Implementação

- [ ] Branch criado (`feature/melhorias-fase-X`)
- [ ] Commits pendentes pushados
- [ ] Testes atuais passando

### Pós-Fase 1

- [ ] flutter analyze sem erros
- [ ] Todos os testes passando
- [ ] Aplicação rodando sem crashes
- [ ] Memória não vazando

### Pós-Fase 2

- [ ] Connection pool funcionando
- [ ] Streaming testado com 100k+ linhas
- [ ] Prepared statements em uso
- [ ] Retry funcionando em falhas
- [ ] Métricas sendo coletadas
- [ ] Performance 50%+ melhor

### Pós-Fase 3

- [ ] Nenhum import de Infrastructure em Application
- [ ] DI movido para camadas corretas
- [ ] Funções < 20 linhas
- [ ] analyze sem warnings
- [ ] Cancelamento funcionando

### Pós-Fase 4

- [ ] 80%+ cobertura de testes
- [ ] Todos os widgets testados
- [ ] UI responsiva e acessível
- [ ] Localização funcionando
- [ ] Documentação atualizada

---

## Estratégia de Commits

### Fase 1

```
git commit -m "feat: remove deprecated dependencies and fix critical issues"
- Remove connect_database dependency
- Fix throw Exception in ODBC gateway
- Add mounted checks to prevent crashes
- Extract response creation methods
- Add spacing constants
- Add const constructors
- Close StreamController properly
```

### Fase 2

```
git commit -m "feat: implement connection pooling and streaming for performance"
- Add IConnectionPool interface and implementation
- Integrate pool with OdbcDatabaseGateway
- Implement streaming for large queries
- Add progress indicators for streaming
- Enforce prepared statements
- Add retry mechanism with exponential backoff
- Implement metrics collection
```

### Fase 3

```
git commit -m "refactor: fix architecture violations and improve code quality"
- Create ICompressor and IQueryNormalizer interfaces
- Remove Infrastructure imports from Application layer
- Move DI setup to appropriate layers
- Refactor long methods in ODBC gateway
- Extract event handlers from SocketIOTransportClient
- Improve error handling with specific exception types
- Add UI string constants
- Enhance code analysis rules
- Implement query cancellation support
```

### Fase 4

```
git commit -m "test: add comprehensive test coverage and UX improvements"
- Add unit tests for ODBC gateway
- Add unit tests for connection pool
- Add unit tests for services
- Add widget tests for critical components
- Add provider tests
- Implement empty states
- Add loading indicators
- Improve error messages
- Add keyboard shortcuts
- Implement localization
```

---

## Critérios de Sucesso

### Métricas Técnicas

- ✅ **Test Coverage**: >80%
- ✅ **Analyze**: 0 errors, 0 warnings
- ✅ **Performance**: Queries 50%+ mais rápidas
- ✅ **Memory**: Sem vazamentos em operações normais
- ✅ **Architecture**: 0 violações de Clean Architecture

### Métricas de Qualidade

- ✅ **Funções**: Todas <20 linhas
- ✅ **Classes**: SRP respeitado
- ✅ **Duplicação**: <3% de código duplicado
- ✅ **Const**: 90%+ de widgets elegíveis são const

### Métricas de UX

- ✅ **Loading**: Todo async tem indicador
- ✅ **Errors**: Mensagens acionáveis
- ✅ **Empty States**: Guias úteis
- ✅ **Acessibilidade**: Labels semânticos
- ✅ **Keyboard**: Atalhos funcionando

---

## Riscos e Mitigações

| Risco                                | Probabilidade | Impacto | Mitigação                             |
| ------------------------------------ | ------------- | ------- | ------------------------------------- |
| **Quebrar funcionalidade existente** | Média         | Alto    | Testes abrangentes antes de cada fase |
| **Performance piorar com pool**      | Baixa         | Médio   | Benchmark antes/depois, métricas      |
| **Streaming aumentar complexidade**  | Média         | Médio   | Implementar como feature opcional     |
| **Tests falsos (mocks incorretos)**  | Média         | Alto    | Revisar mocks, testar com DB real     |
| **Regressões em UI**                 | Baixa         | Médio   | Widget tests, testes manuais          |

---

## Próximos Passos

1. **Aprovar plano** - Revisar prioridades com time
2. **Criar branch** - `feature/melhorias-fase1`
3. **Iniciar Fase 1** - Começar com Quick Wins
4. **Validar continuamente** - Testes + analyze após cada tarefa
5. **Documentar aprendizados** - Atualizar plano conforme necessário

---

**Status**: 📝 Planejamento - Aguardando aprovação
**Próximo início**: Após aprovação do stakeholder
