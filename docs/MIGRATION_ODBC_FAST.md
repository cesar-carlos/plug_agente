# Plano de Migração: connect_database → odbc_fast

**Data**: 30/01/2026
**Versão odbc_fast**: 0.3.1
**Status**: Planejamento

---

## Sumário Executivo

Este documento descreve a migração do pacote `connect_database: ^1.0.0` (DESContinuado) para `odbc_fast: ^0.3.1` (Enterprise-grade com Rust native engine).

**Benefícios Principais**:

- Motor nativo em Rust (performance superior)
- API assíncrona real (non-blocking) - ideal para Flutter
- Clean Architecture embutida no pacote
- Conexão por pool nativo
- Streaming de resultados (para grandes datasets)
- Prepared statements com tipos
- Bulk insert (protocolo binário)
- Métricas e observabilidade
- Savepoints (transações aninhadas)
- Retry automático com exponential backoff

**Impacto Estimado**: 3-5 dias de desenvolvimento

---

## 1. Comparação: connect_database vs odbc_fast

### 1.1 Arquitetura

| Aspecto                 | connect_database     | odbc_fast               |
| ----------------------- | -------------------- | ----------------------- |
| **Motor nativo**        | C++ (via dart:ffi)   | **Rust (via dart:ffi)** |
| **Arquitetura**         | Simples              | **Clean Architecture**  |
| **API Assíncrona**      | ❌ Não               | ✅ **Sim (isolates)**   |
| **Streaming**           | ❌ Não               | ✅ **Sim**              |
| **Connection Pool**     | ❌ Não               | ✅ **Sim (nativo)**     |
| **Prepared Statements** | ✅ Sim               | ✅ **Sim + tipos**      |
| **Bulk Operations**     | ❌ Não               | ✅ **Sim (binário)**    |
| **Métricas**            | ❌ Não               | ✅ **Sim**              |
| **Retry Automático**    | ❌ Não               | ✅ **Sim**              |
| **Savepoints**          | ❌ Não               | ✅ **Sim**              |
| **Status**              | ⚠️ **Descontinuado** | ✅ **Ativo**            |

### 1.2 API - Principais Diferenças

#### **Conexão**

**connect_database**:

```dart
final config = DatabaseConfig.sqlServer(
  driverName: 'SQL Server',
  username: 'user',
  password: 'pass',
  database: 'MyDB',
  server: 'localhost',
  port: 1433,
);

final command = SqlCommand(config);
final result = await command.connect();
// command.execute(), command.open(), etc.
```

**odbc_fast**:

```dart
final service = OdbcService(repository);
await service.initialize();

// Connection String Builder
final connStr = SqlServerBuilder()
  .server('localhost')
  .port(1433)
  .database('MyDB')
  .credentials('user', 'pass')
  .build();

final connResult = await service.connect(connStr);
// ID da conexão retornada em connResult.getOrNull()
```

#### **Execução de Query**

**connect_database**:

```dart
command.commandText = 'SELECT * FROM users';
final result = await command.open(); // ou command.execute()
// Iteração manual com while (!command.eof)
```

**odbc_fast**:

```dart
// Simples
final result = await service.executeQuery(connectionId, 'SELECT * FROM users');
// Result: QueryResult(columns, rows, rowCount)

// Com parâmetros
final result = await service.executeQueryParams(
  connectionId,
  'SELECT * FROM users WHERE id = ?',
  [123],
);

// Streaming (para grandes datasets)
await for (final chunk in native.streamQueryBatched(connectionId, query)) {
  // chunk.columns, chunk.rows, chunk.rowCount
}
```

#### **Transações**

**connect_database**:

```dart
// Não tem transações explícitas na API pública
// Depende de autocommit do ODBC
```

**odbc_fast**:

```dart
// Iniciar transação
final txnId = await service.beginTransaction(
  connectionId,
  IsolationLevel.readCommitted,
);

// Commit
await service.commitTransaction(connectionId, txnId);

// Rollback
await service.rollbackTransaction(connectionId, txnId);

// Savepoints (nested transactions)
await service.createSavepoint(connectionId, txnId, 'sp1');
await service.rollbackToSavepoint(connectionId, txnId, 'sp1');
```

---

## 2. Análise de Código Removível

### 2.1 `OdbcDatabaseGateway` - `odbc_database_gateway.dart`

**Código que pode ser REMOVIDO**:

#### **1. Função `_extractColumnNames` (linhas 82-121)**

```dart
// ❌ REMOVER: Não é mais necessário extrair colunas manualmente
List<String> _extractColumnNames(String query) {
  final upperQuery = query.toUpperCase().trim();
  if (!upperQuery.startsWith('SELECT')) {
    return [];
  }
  // ... 40 linhas de parsing manual de SQL
}
```

**Por quê?** `odbc_fast.QueryResult` já retorna `columns` automaticamente.

#### **2. Função `_getColumnNamesFromTable` (linhas 144-163)**

```dart
// ❌ REMOVER: Não é mais necessário buscar colunas da tabela
Future<List<String>> _getColumnNamesFromTable(db.SqlCommand command, String query) async {
  // Usa TableMetadata para buscar colunas
  // odbc_fast já retorna isso em QueryResult
}
```

**Por quê?** `odbc_fast` já inclui metadados de colunas nos resultados.

#### **3. Função `_getColumnMetadata` (linhas 165-191)**

```dart
// ❌ REMOVER: Implementação manual de metadados
Future<List<Map<String, dynamic>>> _getColumnMetadata(...) async {
  // Query manual de ODBC catalog
}
```

**Por quê?** Use `service.catalogColumns()` do `odbc_fast`.

#### **4. Função `_extractFieldValue` (linhas 193-228)**

```dart
// ❌ REMOVER: Extração manual de valores por tipo
dynamic _extractFieldValue(db.SqlCommand command, String columnName) {
  // Tenta asString, asInt, asDouble, asBool, asDate
  // odbc_fast já faz isso automaticamente
}
```

**Por quê?** `odbc_fast.QueryResult.rows` já contém valores convertidos.

#### **5. Função `_iterateWithOpen` (linhas 230-264)**

```dart
// ❌ REMOVER: Iteração manual de resultados
Future<Result<List<Map<String, dynamic>>>> _iterateWithOpen(...) async {
  while (!command.eof) {
    // Iteração linha por linha
  }
}
```

**Por quê?** `odbc_fast` retorna `QueryResult.rows` diretamente (ou use streaming).

#### **6. Lógica de `_filterSafeColumns` (linhas 123-142)**

```dart
// ❌ REMOVER: Filtro manual de tipos binários
List<Map<String, dynamic>> _filterSafeColumns(List<Map<String, dynamic>> columns) {
  const binaryTypes = ['BLOB', 'VARBINARY', ...];
  // Filtra colunas binárias
}
```

**Por quê?** `odbc_fast` já trata tipos binários automaticamente.

### 2.2 `ExecutePlaygroundQuery` - Application Layer

**Código que pode ser REMOVIDO**:

```dart
// ❌ REMOVER: Validação manual de SELECT
if (!trimmedQuery.toUpperCase().startsWith('SELECT')) {
  return Failure(domain.ValidationFailure(
    'Apenas consultas SELECT são permitidas...'
  ));
}
```

**Por quê?** `odbc_fast` suporta qualquer tipo de query (SELECT, INSERT, UPDATE, DELETE, etc.). A validação pode ser feita na UI se necessário.

### 2.3 Mapeamento de Tipos de Database

**Arquivo**: `infrastructure/config/database_type.dart`

**MANTER**, mas simplificar:

```dart
// ✅ SIMPLIFICAR: Apenas para info de UI/Connection String Builder
enum DatabaseType {
  sqlServer,
  postgresql,
  sybaseAnywhere,
}
```

**Connection String Builder do odbc_fast**:

```dart
// ✅ Usar SqlServerBuilder, PostgresBuilder do odbc_fast
final connStr = SqlServerBuilder()
  .server(config.host)
  .port(config.port)
  .database(config.databaseName)
  .credentials(config.username, config.password)
  .build();
```

---

## 3. Novas Funcionalidades do odbc_fast

### 3.1 API Assíncrona Real (Non-Blocking)

**Para Flutter (RECOMENDADO)**:

```dart
// No main.dart ou inicialização do app
final locator = ServiceLocator();
locator.initialize(useAsync: true);

// No provider/serviço
final asyncService = locator.asyncService;
await asyncService.initialize();

// Todas as operações são non-blocking (UI nunca trava)
final result = await asyncService.executeQuery(connectionId, query);
```

**Benefícios**:

- Queries longas não travam a UI
- Operações em isolate dedicado
- Overhead: ~1-3ms por operação

### 3.2 Connection Pool Nativo

```dart
// Criar pool
final poolIdResult = await service.poolCreate(connectionString, maxSize: 4);
await poolIdResult.fold((poolId) async {
  // Usar pool
  final connResult = await service.poolGetConnection(poolId);

  // ... operações

  // Liberar conexão de volta ao pool
  await service.poolReleaseConnection(connectionId);

  // Health check
  await service.poolHealthCheck(poolId);

  // Estado do pool
  final state = await service.poolGetState(poolId);
  print('Active: ${state.activeConnections}, Idle: ${state.idleConnections}');

  // Fechar pool
  await service.poolClose(poolId);
}, (error) async {});
```

**Benefícios**:

- Reutilização de conexões
- Melhor performance
- Health check automático
- Estado monitorável

### 3.3 Streaming de Resultados

```dart
final native = NativeOdbcConnection();
await native.initialize();
final connId = native.connect(dsn);

// Streaming com batching (cursor-based)
await for (final chunk in native.streamQueryBatched(
  connId,
  'SELECT * FROM huge_table',
  fetchSize: 1000,    // linhas por batch
  chunkSize: 1024 * 1024, // buffer em bytes
)) {
  // chunk.columns, chunk.rows, chunk.rowCount
  // Processar chunk e renderizar na UI
}
```

**Benefícios**:

- Memória constante (não carrega tudo de uma vez)
- UI responsiva com progresso
- Ideal para tabelas grandes

### 3.4 Bulk Insert (Protocolo Binário)

```dart
final builder = BulkInsertBuilder()
  .table('my_table')
  .addColumn('id', BulkColumnType.i32)
  .addColumn('name', BulkColumnType.text, maxLen: 64)
  .addColumn('created_at', BulkColumnType.timestamp)
  .addRow([1, 'Alice', DateTime.now()])
  .addRow([2, 'Bob', DateTime.now()])
  .addRow([3, 'Charlie', DateTime.now()]);

await service.bulkInsert(
  connectionId,
  builder.tableName,
  builder.columnNames,
  builder.build(),
  builder.rowCount,
);
```

**Benefícios**:

- 10-100x mais rápido que INSERT individual
- Protocolo binário nativo
- Single roundtrip ao banco

### 3.5 Métricas e Observabilidade

```dart
final metrics = await service.getMetrics();
await metrics.fold((m) async {
  print('Queries executadas: ${m.queryCount}');
  print('Erros: ${m.errorCount}');
  print('Uptime: ${m.uptime}');
  print('Latência média: ${m.avgLatencyMs}ms');
  print('Latência P99: ${m.p99LatencyMs}ms');
}, (error) async {});
```

**Benefícios**:

- Monitoramento de performance
- Debug de problemas
- Alertas baseados em métricas

### 3.6 Retry Automático com Exponential Backoff

```dart
final result = await service.withRetry(
  () => service.connect(dsn),
  options: RetryOptions(
    maxAttempts: 3,
    initialDelay: Duration(milliseconds: 100),
    maxDelay: Duration(seconds: 10),
    backoffMultiplier: 2.0,
  ),
);
```

**Benefícios**:

- Recovery automático de erros transitórios
- Configurável
- Exponential backoff inteligente

### 3.7 Catalog/Metadata Queries

```dart
// Tabelas
final tables = await service.catalogTables(
  connectionId,
  catalog: 'my_db',
  schema: 'dbo',
);

// Colunas de uma tabela
final columns = await service.catalogColumns(connectionId, 'users');

// Tipos suportados
final types = await service.catalogTypeInfo(connectionId);
```

**Benefícios**:

- Introspecção do banco
- Auto-complete de SQL
- Validação de schemas

---

## 4. Melhorias na UI

### 4.1 Playground Page

#### **Adicionar: Indicador de Progresso para Queries Longas**

```dart
// Mostrar progresso durante execução longa
Widget _buildQueryProgress() {
  if (!playgroundProvider.isExecuting) return const SizedBox.shrink();

  final progress = playgroundProvider.executionProgress; // 0.0 a 1.0
  final rowsProcessed = playgroundProvider.rowsProcessed;
  final totalRows = playgroundProvider.totalRows; // null se desconhecido

  return Column(
    children: [
      ProgressBar(value: progress),
      Text(totalRows != null
        ? 'Processando: $rowsProcessed de $totalRows linhas'
        : 'Processando: $rowsProcessed linhas'),
    ],
  );
}
```

**Implementação com streaming do odbc_fast**:

```dart
// No provider
final asyncService = locator.asyncService;

Future<void> executeQuery() async {
  _isLoading = true;
  _results = [];
  _rowsProcessed = 0;
  notifyListeners();

  final native = AsyncNativeOdbcConnection();
  await native.initialize();
  final connId = await native.connect(_connectionString);

  // Streaming
  await for (final chunk in native.streamQueryBatched(
    connId,
    _query,
    fetchSize: 1000,
    chunkSize: 1024 * 1024,
  )) {
    // Converter chunk.rows para Map<String, dynamic>
    final rows = _convertChunkToMaps(chunk);
    _results.addAll(rows);
    _rowsProcessed += chunk.rowCount;

    // Atualizar progresso
    _executionProgress = _calculateProgress();
    notifyListeners(); // UI atualiza a cada chunk
  }

  await native.disconnect(connId);
  _isLoading = false;
  notifyListeners();
}
```

#### **Adicionar: Métricas de Execução**

```dart
// Card com métricas
Widget _buildMetricsCard() {
  final duration = playgroundProvider.executionDuration;
  final rowCount = playgroundProvider.results.length;

  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(FluentIcons.clock, size: 16),
          const SizedBox(width: 8),
          Text('Tempo: ${duration.inMilliseconds}ms'),
          const SizedBox(width: 24),
          Icon(FluentIcons.table, size: 16),
          const SizedBox(width: 8),
          Text('Linhas: $rowCount'),
          const SizedBox(width: 24),
          Icon(FluentIcons.database, size: 16),
          const SizedBox(width: 8),
          Text('Fetch: Batching (1000 linhas)'),
        ],
      ),
    ),
  );
}
```

#### **Adicionar: Cancelamento de Query**

```dart
// Botão de cancelar
SqlActionBar(
  onExecute: _executeQuery,
  onCancel: _cancelQuery, // ← NOVO
  isExecuting: _isLoading,
)

// No provider
VoidCallback? _cancelToken;

Future<void> executeQuery() async {
  // Criar cancel token
  _cancelToken = () {
    // Cancelar query do odbc_fast
    // (se suportado pela versão)
  };
}

void cancelQuery() {
  _cancelToken?.call();
  _isLoading = false;
  notifyListeners();
}
```

### 4.2 Dashboard Page

#### **Adicionar: Card de Métricas ODBC**

```dart
class _OdbcMetricsCard extends StatelessWidget {
  final OdbcMetrics metrics;

  const _OdbcMetricsCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Métricas ODBC', style: context.typography.titleLarge),
            const SizedBox(height: 16),
            _MetricRow(
              icon: FluentIcons.query,
              label: 'Queries Executadas',
              value: metrics.queryCount.toString(),
            ),
            _MetricRow(
              icon: FluentIcons.error_badge,
              label: 'Erros',
              value: metrics.errorCount.toString(),
              valueColor: metrics.errorCount > 0
                ? AppColors.error
                : AppColors.success,
            ),
            _MetricRow(
              icon: FluentIcons.clock,
              label: 'Uptime',
              value: _formatDuration(metrics.uptime),
            ),
            _MetricRow(
              icon: FluentIcons.timer,
              label: 'Latência Média',
              value: '${metrics.avgLatencyMs.toStringAsFixed(2)}ms',
            ),
            _MetricRow(
              icon: FluentIcons.timer,
              label: 'Latência P99',
              value: '${metrics.p99LatencyMs.toStringAsFixed(2)}ms',
            ),
          ],
        ),
      ),
    );
  }
}
```

### 4.3 Config Page

#### **Adicionar: Configuração de Pool**

```dart
class _ConnectionPoolSettings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connection Pool', style: context.typography.titleLarge),
            const SizedBox(height: 16),
            Checkbox(
              content: const Text('Habilitar Connection Pool'),
              checked: configProvider.useConnectionPool,
              onChanged: (checked) {
                configProvider.setUseConnectionPool(checked);
              },
            ),
            if (configProvider.useConnectionPool) ...[
              const SizedBox(height: 16),
              NumberBox(
                label: 'Tamanho Máximo do Pool',
                value: configProvider.poolMaxSize,
                min: 1,
                max: 20,
                onChanged: (value) {
                  configProvider.setPoolMaxSize(value ?? 4);
                },
              ),
              const SizedBox(height: 8),
              InfoLabel(
                'Múltiplas conexões são reutilizadas automaticamente. '
                'Melhora performance em cenários de alta concorrência.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

#### **Adicionar: Timeout de Conexão**

```dart
NumberBox(
  label: 'Login Timeout (segundos)',
  value: configProvider.loginTimeout,
  min: 1,
  max: 120,
  onChanged: (value) {
    configProvider.setLoginTimeout(value ?? 30);
  },
),

Slider(
  label: 'Buffer de Resultados (MB)',
  value: configProvider.maxResultBufferMb.toDouble(),
  min: 8,
  max: 128,
  divisions: 15,
  onChanged: (value) {
    configProvider.setMaxResultBufferMb(value.toInt());
  },
),
```

### 4.4 Query Results Section

#### **Adicionar: Virtualização para Grandes Resultados**

```dart
// Usar ListView.builder com lazy loading
class _QueryResultsDataGrid extends StatelessWidget {
  final List<Map<String, dynamic>> results;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final row = results[index];
        return _ResultRowWidget(row: row);
      },
    );
  }
}

// Ou melhor: usar DataTable com paging
class _QueryResultsDataGrid extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  final int pageSize;
  final int currentPage;

  @override
  Widget build(BuildContext context) {
    final start = currentPage * pageSize;
    final end = min(start + pageSize, results.length);
    final page = results.sublist(start, end);

    return SfDataGrid(
      source: _QueryDataSource(page),
      rowsPerPage: pageSize,
      pageCount: (results.length / pageSize).ceil(),
    );
  }
}
```

---

## 5. Plano de Migração Passo a Passo

### Fase 1: Preparação (1 dia)

#### 1.1 Backup e Setup

- [ ] Criar branch `feature/migrate-odbc-fast`
- [ ] Commitar todas as mudanças pendentes
- [ ] Tag atual versão como `v1.0.0-pre-migration`

#### 1.2 Dependências

- [ ] Adicionar `odbc_fast: ^0.3.1` ao `pubspec.yaml`
- [ ] Executar `flutter pub get`
- [ ] Verificar compatibilidade com outras dependências

#### 1.3 Testes

- [ ] Criar testes de integração para o odbc_fast
- [ ] Testar conexão com cada tipo de banco (SQL Server, PostgreSQL, Sybase)
- [ ] Documentar resultados

---

### Fase 2: Implementação do Adapter (2 dias)

#### 2.1 Criar Adapter para `odbc_fast`

**Arquivo**: `lib/infrastructure/external_services/odbc_fast_database_gateway.dart`

```dart
import 'package:odbc_fast/odbc_fast.dart';
import 'package:result_dart/result_dart.dart';

class OdbcFastDatabaseGateway implements IDatabaseGateway {
  final OdbcService _service;
  final ServiceLocator _locator;

  OdbcFastDatabaseGateway(this._service, this._locator);

  Future<void> initialize({bool useAsync = true}) async {
    _locator.initialize(useAsync: useAsync);
    await _service.initialize();
  }

  @override
  Future<Result<bool>> testConnection(String connectionString) async {
    final connResult = await _service.connect(connectionString);

    return connResult.fold(
      (connection) async {
        await _service.disconnect(connection.id);
        return const Success(true);
      },
      (error) async => Failure(error),
    );
  }

  @override
  Future<Result<QueryResponse>> executeQuery(QueryRequest request) async {
    final connResult = await _service.connect(request.connectionString);

    return connResult.fold(
      (connection) async {
        final result = await _service.executeQuery(
          connection.id,
          request.query,
        );

        await _service.disconnect(connection.id);

        return result.fold(
          (queryResult) {
            final response = QueryResponse(
              id: request.id,
              requestId: request.id,
              agentId: request.agentId,
              data: _convertQueryResultToMaps(queryResult),
              affectedRows: queryResult.rowCount,
              timestamp: DateTime.now(),
              columnMetadata: _extractColumnMetadata(queryResult),
            );
            return Success(response);
          },
          (error) async {
            final errorResponse = QueryResponse(
              id: request.id,
              requestId: request.id,
              agentId: request.agentId,
              data: [],
              timestamp: DateTime.now(),
              error: error.message,
            );
            return Success(errorResponse);
          },
        );
      },
      (error) async {
        final errorResponse = QueryResponse(
          id: request.id,
          requestId: request.id,
          agentId: request.agentId,
          data: [],
          timestamp: DateTime.now(),
          error: error.message,
        );
        return Success(errorResponse);
      },
    );
  }

  List<Map<String, dynamic>> _convertQueryResultToMaps(QueryResult result) {
    return result.rows.map((row) {
      final map = <String, dynamic>{};
      for (var i = 0; i < result.columns.length; i++) {
        map[result.columns[i]] = row[i];
      }
      return map;
    }).toList();
  }

  List<Map<String, dynamic>>? _extractColumnMetadata(QueryResult result) {
    // odbc_fast não retorna metadados de colunas por padrão
    // Use catalogColumns() se necessário
    return null;
  }

  @override
  Future<Result<int>> executeNonQuery(String query, Map<String, dynamic>? parameters) async {
    // Implementar similar ao executeQuery
    // Usar executeQueryParams se houver parâmetros
    return Failure(UnsupportedError('Not implemented'));
  }
}
```

#### 2.2 Atualizar Service Locator

**Arquivo**: `lib/core/di/service_locator.dart`

```dart
import 'package:odbc_fast/odbc_fast.dart' as odbc;

// Adicionar
final getIt.registerLazySingleton<IDatabaseGateway>(
  () => OdbcFastDatabaseGateway(
    getIt<odbc.OdbcService>(),
    odbc.ServiceLocator(),
  ),
);

// Remover antigo
// getIt.registerLazySingleton<IDatabaseGateway>(
//   () => OdbcDatabaseGateway(...),
// );
```

---

### Fase 3: Refatoração e Limpeza (1 dia)

#### 3.1 Remover Código Obsoleto

- [ ] Remover `_extractColumnNames` de `OdbcDatabaseGateway`
- [ ] Remover `_getColumnNamesFromTable`
- [ ] Remover `_getColumnMetadata` implementação manual
- [ ] Remover `_extractFieldValue`
- [ ] Remover `_iterateWithOpen`
- [ ] Remover `_filterSafeColumns`

#### 3.2 Simplificar Use Cases

**Arquivo**: `lib/application/use_cases/execute_playground_query.dart`

```dart
// REMOVER validação de SELECT-only
// ODBC Fast suporta qualquer query

Future<Result<QueryResponse>> call(String query) async {
  final trimmedQuery = query.trim();

  if (trimmedQuery.isEmpty) {
    return Failure(domain.ValidationFailure('A query não pode estar vazia'));
  }

  // ❌ REMOVER ESTE BLOCO
  // if (!trimmedQuery.toUpperCase().startsWith('SELECT')) {
  //   return Failure(domain.ValidationFailure(
  //     'Apenas consultas SELECT são permitidas...'
  //   ));
  // }

  final configResult = await _configRepository.getCurrentConfig();
  // ... resto do código
}
```

#### 3.3 Atualizar Connection String Builder

**Arquivo**: `lib/infrastructure/config/database_config.dart`

```dart
import 'package:odbc_fast/odbc_fast.dart';

String toConnectionString() {
  switch (databaseType) {
    case DatabaseType.sqlServer:
      return SqlServerBuilder()
        .server(server)
        .port(port)
        .database(database)
        .credentials(username, password)
        .build();

    case DatabaseType.postgresql:
      return PostgresBuilder()
        .server(server)
        .port(port)
        .database(database)
        .credentials(username, password)
        .build();

    case DatabaseType.sybaseAnywhere:
      // Sybase pode usar SQL Anywhere Builder ou connection string manual
      return 'Driver={SQL Anywhere};Server=$server;Port=$port;Database=$database;Uid=$username;Pwd=$password';
  }
}
```

---

### Fase 4: Melhorias na UI (1 dia)

#### 4.1 Playground Provider - Adicionar Streaming

```dart
class PlaygroundProvider extends ChangeNotifier {
  final AsyncNativeOdbcConnection _asyncConnection;

  bool _isStreaming = false;
  int _rowsProcessed = 0;
  double _progress = 0.0;

  Future<void> executeQueryWithStreaming() async {
    _isStreaming = true;
    _rowsProcessed = 0;
    _results = [];
    notifyListeners();

    final connId = await _asyncConnection.connect(_connectionString);

    await for (final chunk in _asyncConnection.streamQueryBatched(
      connId,
      _query,
      fetchSize: 1000,
    )) {
      final rows = _convertChunkToMaps(chunk);
      _results.addAll(rows);
      _rowsProcessed += chunk.rowCount;
      _progress = _rowsProcessed / _estimatedTotalRows;
      notifyListeners(); // UI atualiza a cada chunk
    }

    await _asyncConnection.disconnect(connId);
    _isStreaming = false;
    notifyListeners();
  }
}
```

#### 4.2 Adicionar Cards de Métricas

- [ ] `_OdbcMetricsCard` no Dashboard
- [ ] `_QueryMetricsCard` no Playground
- [ ] `_PerformanceMetricsCard` na Config page

#### 4.3 Adicionar Configurações Avançadas

- [ ] Connection Pool settings
- [ ] Login/Connection timeout
- [ ] Buffer size configuration
- [ ] Retry options

---

### Fase 5: Testes e Validação (1 dia)

#### 5.1 Testes Manuais

- [ ] Testar conexão SQL Server
- [ ] Testar conexão PostgreSQL
- [ ] Testar conexão Sybase Anywhere
- [ ] Testar queries SELECT simples
- [ ] Testar queries com JOIN
- [ ] Testar queries com parâmetros
- [ ] Testar queries longas (verificar streaming)
- [ ] Testar error handling

#### 5.2 Testes Automatizados

- [ ] Unit tests para `OdbcFastDatabaseGateway`
- [ ] Integration tests para cenários principais
- [ ] Performance tests (benchmark vs connect_database)

#### 5.3 Validar UI

- [ ] Verificar responsividade durante queries longas
- [ ] Verificar métricas sendo exibidas
- [ ] Verificar cancelamento de queries (se implementado)
- [ ] Verificar progress indicators

---

### Fase 6: Deploy e Monitoramento

#### 6.1 Deploy

- [ ] Merge para `main`
- [ ] Tag version como `v1.1.0`
- [ ] Release notes (changelog)

#### 6.2 Monitoramento

- [ ] Monitorar logs de erro
- [ ] Verificar métricas de performance
- [ ] Coletar feedback de usuários

---

## 6. Riscos e Mitigações

### 6.1 Riscos

| Risco                               | Probabilidade | Impacto | Mitigação                              |
| ----------------------------------- | ------------- | ------- | -------------------------------------- |
| **Compatibilidade de drivers ODBC** | Média         | Alto    | Testar extensivamente todos os drivers |
| **Performance regressions**         | Baixa         | Médio   | Benchmark antes/depois; profiling      |
| **Breaking changes na API**         | Baixa         | Alto    | Adapter pattern; testes abrangentes    |
| **Bugs no odbc_fast**               | Baixa         | Alto    | Reportar issues; workaround            |
| **UI não responsiva com async**     | Baixa         | Médio   | Testar com queries muito longas        |

### 6.2 Rollback Plan

Se problemas críticos forem encontrados:

1. Reverter branch para versão anterior
2. Remover `odbc_fast` do pubspec.yaml
3. Restaurar `connect_database: ^1.0.0`
4. Hotfix release `v1.0.1`

**Nota**: `connect_database` está descontinuado, então esta opção é apenas temporária.

---

## 7. Compatibilidade de Drivers ODBC

### 7.1 SQL Server

**Driver**: `{ODBC Driver 18 for SQL Server}`

```dart
final connStr = SqlServerBuilder()
  .server('localhost')
  .port(1433)
  .database('MyDB')
  .credentials('user', 'pass')
  .build();
```

**Status**: ✅ Suportado

### 7.2 PostgreSQL

**Driver**: `PostgreSQL Unicode`

```dart
final connStr = PostgresBuilder()
  .server('localhost')
  .port(5432)
  .database('mydb')
  .credentials('user', 'pass')
  .build();
```

**Status**: ✅ Suportado

### 7.3 SQL Anywhere (Sybase)

**Driver**: `{SQL Anywhere 17}`

```dart
final connStr = 'Driver={SQL Anywhere 17};Server=myserver;Database=mydb;Uid=user;Pwd=pass';
```

**Status**: ✅ Suportado (connection string manual)

---

## 8. Referências

- [odbc_fast no pub.dev](https://pub.dev/packages/odbc_fast)
- [odbc_fast no GitHub](https://github.com/cesar-carlos/dart_odbc_fast)
- [Documentação odbc_fast](https://github.com/cesar-carlos/dart_odbc_fast/blob/main/README.md)
- [Clean Architecture](../.claude/rules/clean_architecture.md)

---

## 9. Checklist Final

Antes de considerar a migração completa:

### Código

- [ ] `odbc_fast` adicionado ao pubspec.yaml
- [ ] `OdbcFastDatabaseGateway` implementado
- [ ] Código obsoleto removido
- [ ] Use cases simplificados
- [ ] Service locator atualizado

### Testes

- [ ] Testes unitários passando
- [ ] Testes de integração passando
- [ ] Todos os bancos testados

### UI

- [ ] Métricas exibidas corretamente
- [ ] Streaming funcionando
- [ ] Configurações avançadas disponíveis
- [ ] Responsividade OK

### Documentação

- [ ] README atualizado
- [ ] CHANGELOG.md atualizado
- [ ] Comentários no código atualizados

### Deploy

- [ ] Merge para main
- [ ] Version tag criada
- [ ] Release publicado

---

**Aprovado por**: ******\_\_\_******
**Data**: ******\_\_******

---

## Appendix A: Exemplo Completo de Uso

### A.1 Inicialização

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar odbc_fast com async
  final locator = ServiceLocator();
  locator.initialize(useAsync: true);

  final odbcService = locator.asyncService;
  await odbcService.initialize();

  // Injetar no DI container
  getIt.registerSingleton<OdbcService>(odbcService);

  runApp(MyApp());
}
```

### A.2 Executar Query com Streaming

```dart
// playground_provider.dart
class PlaygroundProvider extends ChangeNotifier {
  final AsyncNativeOdbcConnection _odbc;

  Future<void> executeQueryWithProgress(String query) async {
    _isLoading = true;
    _results = [];
    notifyListeners();

    final connId = await _odbc.connect(_connectionString);
    final stopwatch = Stopwatch()..start();

    int totalRows = 0;

    await for (final chunk in _odbc.streamQueryBatched(
      connId,
      query,
      fetchSize: 1000,
      chunkSize: 1024 * 1024,
    )) {
      // Converter chunk para Map<String, dynamic>
      for (final row in chunk.rows) {
        final map = <String, dynamic>{};
        for (var i = 0; i < chunk.columns.length; i++) {
          map[chunk.columns[i]] = row[i];
        }
        _results.add(map);
        totalRows++;
      }

      // Notificar listeners a cada chunk (UI atualiza)
      _rowsProcessed = totalRows;
      _progress = totalRows / _estimatedTotal;
      notifyListeners();
    }

    stopwatch.stop();
    _executionDuration = stopwatch.elapsed;

    await _odbc.disconnect(connId);
    _isLoading = false;
    notifyListeners();
  }
}
```

### A.3 Métricas em Tempo Real

```dart
// dashboard_page.dart
class _DashboardPageState extends State<DashboardPage> {
  OdbcMetrics? _metrics;
  Timer? _metricsTimer;

  @override
  void initState() {
    super.initState();
    _updateMetrics();
    _metricsTimer = Timer.periodic(Duration(seconds: 5), (_) => _updateMetrics());
  }

  Future<void> _updateMetrics() async {
    final odbcService = getIt<OdbcService>();
    final result = await odbcService.getMetrics();
    result.fold((metrics) {
      setState(() {
        _metrics = metrics;
      });
    }, (error) {});
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      content: _metrics == null
        ? const ProgressRing()
        : _OdbcMetricsCard(metrics: _metrics!),
    );
  }
}
```

---

**Fim do Plano de Migração**
