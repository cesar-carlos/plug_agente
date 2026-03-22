import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_database_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockOdbcService extends Mock implements OdbcService {}

class MockAgentConfigRepository extends Mock
    implements IAgentConfigRepository {}

class MockConnectionPool extends Mock implements IConnectionPool {}

void main() {
  group('OdbcDatabaseGateway', () {
    late MockOdbcService mockService;
    late MockAgentConfigRepository mockConfigRepository;
    late MockConnectionPool mockConnectionPool;
    late IRetryManager retryManager;
    late MetricsCollector metrics;
    late MockOdbcConnectionSettings mockSettings;
    late OdbcDatabaseGateway gateway;

    setUp(() {
      mockService = MockOdbcService();
      mockConfigRepository = MockAgentConfigRepository();
      mockConnectionPool = MockConnectionPool();
      retryManager = RetryManager();
      metrics = MetricsCollector()..clear();
      mockSettings = MockOdbcConnectionSettings();
      gateway = OdbcDatabaseGateway(
        mockConfigRepository,
        mockService,
        mockConnectionPool,
        retryManager,
        metrics,
        mockSettings,
      );
      when(
        () => mockConnectionPool.warmIdleLeases(any()),
      ).thenAnswer((_) async => const Success(unit));
    });

    group('testConnection and bootstrap failures', () {
      test('testConnection should reject empty connection string', () async {
        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.testConnection('  ');

        expect(result.isError(), isTrue);
        expect(
          result.exceptionOrNull(),
          isA<domain.ValidationFailure>(),
        );
      });

      test(
        'testConnection should succeed when connect and disconnect succeed',
        () async {
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          const connectionId = 'test-conn-1';

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(
            () => mockService.connect(
              connectionString,
              options: any(named: 'options'),
            ),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: connectionId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(() => mockService.disconnect(connectionId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          final result = await gateway.testConnection(connectionString);

          expect(result.getOrNull(), isTrue);
          verify(() => mockService.disconnect(connectionId)).called(1);
        },
      );

      test('testConnection should map connect failure', () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(
          () => mockService.connect(
            connectionString,
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async {
          return const Failure(
            QueryError(message: 'Login failed for user'),
          );
        });

        final result = await gateway.testConnection(connectionString);

        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<domain.ConnectionFailure>());
      });

      test(
        'testConnection should map disconnect failure after successful connect',
        () async {
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          const connectionId = 'test-conn-2';

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(
            () => mockService.connect(
              connectionString,
              options: any(named: 'options'),
            ),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: connectionId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(() => mockService.disconnect(connectionId)).thenAnswer((
            _,
          ) async {
            return const Failure(
              QueryError(message: 'disconnect failed'),
            );
          });

          final result = await gateway.testConnection(connectionString);

          expect(result.isError(), isTrue);
          expect(result.exceptionOrNull(), isA<domain.Failure>());
        },
      );

      test('executeQuery should fail when ODBC initialize fails', () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-init-fail',
          agentId: config.agentId,
          query: 'SELECT 1',
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Failure(
            QueryError(message: 'ODBC environment init failed'),
          );
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        expect(result.exceptionOrNull(), isA<domain.ConnectionFailure>());
        verifyNever(() => mockConfigRepository.getCurrentConfig());
      });

      test('executeQuery should fail when config repository fails', () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-cfg-fail',
          agentId: config.agentId,
          query: 'SELECT 1',
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Failure(domain.NotFoundFailure('config'));
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        final failure =
            result.exceptionOrNull()! as domain.ConfigurationFailure;
        expect(
          failure.message,
          contains('Failed to load database configuration'),
        );
        verifyNever(() => mockConnectionPool.acquire(any()));
      });

      test(
        'executeQuery should reuse cached config across hot calls',
        () async {
          const pooledConnectionId = 'pool-cache';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final requestA = QueryRequest(
            id: 'req-cache-1',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );
          final requestB = QueryRequest(
            id: 'req-cache-2',
            agentId: config.agentId,
            query: 'SELECT 2',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledConnectionId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledConnectionId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer(
            (_) async => const Success(unit),
          );

          final first = await gateway.executeQuery(requestA);
          final second = await gateway.executeQuery(requestB);

          expect(first.isSuccess(), isTrue);
          expect(second.isSuccess(), isTrue);
          verify(() => mockConfigRepository.getCurrentConfig()).called(1);
        },
      );

      test(
        'executeQuery should deduplicate concurrent config loads when cache is cold',
        () async {
          const pooledConnectionId = 'pool-cache-cold';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final requestA = QueryRequest(
            id: 'req-cache-cold-1',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );
          final requestB = QueryRequest(
            id: 'req-cache-cold-2',
            agentId: config.agentId,
            query: 'SELECT 2',
            timestamp: DateTime.now(),
          );
          final gate = Completer<void>();

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            await gate.future;
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledConnectionId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledConnectionId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer(
            (_) async => const Success(unit),
          );

          final firstFuture = gateway.executeQuery(requestA);
          final secondFuture = gateway.executeQuery(requestB);
          await Future<void>.delayed(const Duration(milliseconds: 1));
          gate.complete();

          final first = await firstFuture;
          final second = await secondFuture;

          expect(first.isSuccess(), isTrue);
          expect(second.isSuccess(), isTrue);
          verify(() => mockConfigRepository.getCurrentConfig()).called(1);
        },
      );

      test(
        'executeQuery should map generic pooled query failure without pool fallback',
        () async {
          const pooledConnectionId = 'pool-query-fail';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final request = QueryRequest(
            id: 'req-query-fail',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledConnectionId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledConnectionId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              QueryError(
                message:
                    'Arithmetic overflow during data type conversion in batch',
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer(
            (
              _,
            ) async {
              return const Success(unit);
            },
          );

          final result = await gateway.executeQuery(request);

          expect(result.isError(), isTrue);
          expect(
            result.exceptionOrNull(),
            isA<domain.QueryExecutionFailure>(),
          );
          verifyNever(
            () => mockService.connect(any(), options: any(named: 'options')),
          );
          verify(
            () => mockConnectionPool.release(pooledConnectionId),
          ).called(1);
        },
      );

      test(
        'executeQuery should return timeout failure and cancel connection',
        () async {
          const pooledConnectionId = 'pool-timeout';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final request = QueryRequest(
            id: 'req-timeout',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledConnectionId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledConnectionId,
            ),
          ).thenAnswer((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 400));
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockService.disconnect(pooledConnectionId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer(
            (
              _,
            ) async {
              return const Success(unit);
            },
          );
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeQuery(
            request,
            timeout: const Duration(milliseconds: 50),
          );

          expect(result.isError(), isTrue);
          expect(
            result.exceptionOrNull(),
            isA<domain.QueryExecutionFailure>(),
          );
          verify(() => mockService.disconnect(pooledConnectionId)).called(1);
          verify(
            () => mockConnectionPool.release(pooledConnectionId),
          ).called(1);
          expect(metrics.timeoutCancelSuccessCount, greaterThanOrEqualTo(1));
        },
      );

      test('executeBatch should fail when pool acquire fails', () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return Failure(
            domain.ConnectionFailure.withContext(
              message: 'Pool exhausted',
              context: const {'poolExhausted': true},
            ),
          );
        });

        final result = await gateway.executeBatch(
          config.agentId,
          const [SqlCommand(sql: 'SELECT 1')],
        );

        expect(result.isError(), isTrue);
        expect(metrics.connectionPoolAcquireFailureCount, 1);
      });
    });

    group('executeNonQuery', () {
      test('should return row count on success', () async {
        const pooledId = 'pool-nq-ok';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return const Success(pooledId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: pooledId,
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(
              columns: [],
              rows: [],
              rowCount: 42,
            ),
          );
        });
        when(() => mockConnectionPool.release(pooledId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });

        final result = await gateway.executeNonQuery(
          'UPDATE t SET x = 1',
          null,
        );

        expect(result.getOrNull(), 42);
        verify(
          () => mockService.executeQuery(
            any(),
            connectionId: pooledId,
          ),
        ).called(1);
        verifyNever(
          () => mockService.executeQueryNamed(
            any(),
            any(),
            any(),
          ),
        );
      });

      test(
        'should use executeQueryNamed when parameters are non-empty',
        () async {
          const pooledId = 'pool-nq-named';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQueryNamed(
              pooledId,
              any(),
              any(),
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: [],
                rows: [],
                rowCount: 3,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          final result = await gateway.executeNonQuery(
            'UPDATE t SET x = :v',
            const <String, dynamic>{'v': 1},
          );

          expect(result.getOrNull(), 3);
          verify(
            () => mockService.executeQueryNamed(
              pooledId,
              any(),
              any(),
            ),
          ).called(1);
        },
      );

      test('should map config repository failure', () async {
        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Failure(domain.NotFoundFailure('cfg'));
        });

        final result = await gateway.executeNonQuery('SELECT 1', null);

        expect(result.isError(), isTrue);
        expect(
          result.exceptionOrNull(),
          isA<domain.ConfigurationFailure>(),
        );
      });

      test(
        'should record pool metric when acquire fails (with retries)',
        () async {
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return Failure(Exception('no pool'));
          });

          final result = await gateway.executeNonQuery('SELECT 1', null);

          expect(result.isError(), isTrue);
          // Generic pool errors map to ConnectionFailure without retryable/poolExhausted.
          expect(metrics.connectionPoolAcquireFailureCount, 1);
        },
      );

      test('should map pooled query error without direct fallback', () async {
        const pooledId = 'pool-nq-err';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return const Success(pooledId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: pooledId,
          ),
        ).thenAnswer((_) async {
          return const Failure(QueryError(message: 'syntax error'));
        });
        when(() => mockConnectionPool.release(pooledId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });

        final result = await gateway.executeNonQuery('SELECT 1', null);

        expect(result.isError(), isTrue);
        verifyNever(
          () => mockService.connect(any(), options: any(named: 'options')),
        );
      });

      test(
        'should fall back to direct connection when pool id is invalid',
        () async {
          const pooledId = 'bad-nq';
          const directId = 'direct-nq';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              ValidationError(message: 'Invalid connection ID: bad-nq'),
            );
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: directId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: directId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: [],
                rows: [],
                rowCount: 9,
              ),
            );
          });
          when(() => mockService.disconnect(directId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeNonQuery(
            'UPDATE t SET x = 1',
            null,
          );

          expect(result.getOrNull(), 9);
          verify(() => mockService.disconnect(directId)).called(1);
          verify(() => mockConnectionPool.recycle(any())).called(1);
        },
      );

      test(
        'should timeout non-query, cancel connection, and record cancel metric',
        () async {
          const pooledId = 'pool-nq-to';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockService.disconnect(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeNonQuery(
            'SELECT 1',
            null,
            timeout: const Duration(milliseconds: 30),
          );

          expect(result.isError(), isTrue);
          expect(
            result.exceptionOrNull(),
            isA<domain.QueryExecutionFailure>(),
          );
          verify(() => mockService.disconnect(pooledId)).called(1);
          expect(metrics.timeoutCancelSuccessCount, greaterThanOrEqualTo(1));
        },
      );

      test(
        'should record timeout cancel failure when disconnect returns error',
        () async {
          const pooledId = 'pool-nq-tofail';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final priorFailures = metrics.timeoutCancelFailureCount;

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockService.disconnect(pooledId)).thenAnswer((
            _,
          ) async {
            return const Failure(QueryError(message: 'disconnect failed'));
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeNonQuery(
            'SELECT 1',
            null,
            timeout: const Duration(milliseconds: 30),
          );

          expect(result.isError(), isTrue);
          expect(
            metrics.timeoutCancelFailureCount,
            greaterThan(priorFailures),
          );
        },
      );
    });

    group('executeQuery direct fallback and connection string', () {
      test(
        'should run direct connection when pooled query reports buffer too small',
        () async {
          const pooledId = 'pool-buf';
          const directId = 'direct-buf';
          const connectionString =
              'Driver={ODBC Driver};Server=localhost;DATABASE=master;';
          final config = _buildConfig(connectionString);
          final request = QueryRequest(
            id: 'req-buf-fallback',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              QueryError(message: 'buffer too small for result'),
            );
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: directId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: directId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockService.disconnect(directId)).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeQuery(request);

          expect(result.isSuccess(), isTrue);
          verify(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).called(1);
          verify(() => mockService.disconnect(directId)).called(1);
        },
      );

      test(
        'should map query failure when direct retry after buffer error fails',
        () async {
          const pooledId = 'pool-buf-fail';
          const directId = 'direct-buf-fail';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final request = QueryRequest(
            id: 'req-buf-direct-fail',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              QueryError(message: 'buffer too small'),
            );
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: directId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: directId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              QueryError(message: 'deadlock victim when accessing resource'),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockService.disconnect(directId)).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeQuery(request);

          expect(result.isError(), isTrue);
          expect(
            result.exceptionOrNull(),
            isA<domain.QueryExecutionFailure>(),
          );
        },
      );

      test(
        'should map connection failure when direct connect fails after buffer error',
        () async {
          const pooledId = 'pool-buf-conn';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final request = QueryRequest(
            id: 'req-buf-conn-fail',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              QueryError(message: 'buffer too small'),
            );
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return const Failure(QueryError(message: 'login failed'));
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeQuery(request);

          expect(result.isError(), isTrue);
          expect(result.exceptionOrNull(), isA<domain.ConnectionFailure>());
        },
      );

      test(
        'should map timeout on direct connection after buffer retry',
        () async {
          const pooledId = 'pool-buf-to';
          const directId = 'direct-buf-to';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final request = QueryRequest(
            id: 'req-buf-timeout',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              QueryError(message: 'buffer too small'),
            );
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: directId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: directId,
            ),
          ).thenAnswer((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 400));
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockService.disconnect(directId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeQuery(
            request,
            timeout: const Duration(milliseconds: 50),
          );

          expect(result.isError(), isTrue);
          expect(
            result.exceptionOrNull(),
            isA<domain.QueryExecutionFailure>(),
          );
          verify(() => mockService.disconnect(directId)).called(2);
        },
      );

      test(
        'executeQuery timeout cancel should treat disconnect throw as failure',
        () async {
          const pooledId = 'pool-q-to-throw';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final request = QueryRequest(
            id: 'req-q-to-throw',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );
          final prior = metrics.timeoutCancelFailureCount;

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 400));
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockService.disconnect(pooledId)).thenAnswer((_) async {
            throw StateError('disconnect exploded');
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeQuery(
            request,
            timeout: const Duration(milliseconds: 30),
          );

          expect(result.isError(), isTrue);
          expect(metrics.timeoutCancelFailureCount, greaterThan(prior));
        },
      );

      test(
        'should pass database override into pool acquire connection string',
        () async {
          const pooledId = 'pool-db-ov';
          const baseCs =
              'Driver={ODBC Driver};Server=localhost;DATABASE=master;UID=u;';
          final config = _buildConfig(baseCs);
          final request = QueryRequest(
            id: 'req-db-ov',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          final result = await gateway.executeQuery(
            request,
            database: 'other_db',
          );

          expect(result.isSuccess(), isTrue);
          final captured =
              verify(
                    () => mockConnectionPool.acquire(captureAny()),
                  ).captured.single
                  as String;
          expect(captured.toUpperCase(), contains('DATABASE=OTHER_DB'));
          expect(captured.toUpperCase(), isNot(contains('DATABASE=MASTER')));
        },
      );

      test(
        'should override Initial Catalog segment when database override is set',
        () async {
          const pooledId = 'pool-ic-ov';
          const baseCs =
              'Driver={ODBC Driver};Server=localhost;Initial Catalog=master;';
          final config = _buildConfig(baseCs);
          final request = QueryRequest(
            id: 'req-ic-ov',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          await gateway.executeQuery(request, database: 'catalog_db');

          final captured =
              verify(
                    () => mockConnectionPool.acquire(captureAny()),
                  ).captured.single
                  as String;
          expect(
            captured.toLowerCase(),
            contains('initial catalog=catalog_db'),
          );
        },
      );

      test(
        'should override dbn= segment when database override is set',
        () async {
          const pooledId = 'pool-dbn-ov';
          const baseCs = 'Driver={SQL Anywhere};Server=s;dbn=mydb;UID=u;';
          final config = _buildConfig(
            baseCs,
            driverName: 'SQL Anywhere',
          );
          final request = QueryRequest(
            id: 'req-dbn-ov',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          await gateway.executeQuery(request, database: 'other');

          final captured =
              verify(
                    () => mockConnectionPool.acquire(captureAny()),
                  ).captured.single
                  as String;
          expect(captured.toLowerCase(), contains('dbn=other'));
          expect(captured.toLowerCase(), isNot(contains('dbn=mydb')));
        },
      );

      test(
        'should append DATABASE= when override has no existing database token',
        () async {
          const pooledId = 'pool-append-db';
          const baseCs = 'Driver={ODBC Driver};Server=localhost;UID=u;';
          final config = _buildConfig(baseCs);
          final request = QueryRequest(
            id: 'req-append-db',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          await gateway.executeQuery(request, database: 'appended');

          final captured =
              verify(
                    () => mockConnectionPool.acquire(captureAny()),
                  ).captured.single
                  as String;
          expect(captured.toUpperCase(), contains('DATABASE=APPENDED'));
        },
      );

      test(
        'should hit sql preview truncation for long vacuous multi-result fallback',
        () async {
          const pooledConnectionId = 'pool-long-sql';
          const directConnectionId = 'direct-long-sql';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final longSql = StringBuffer('SELECT 1 AS a');
          for (var i = 0; i < 40; i++) {
            longSql.write(' /*p$i*/');
          }
          longSql.write('; SELECT 2 AS b;');
          final sql = longSql.toString();
          final config = _buildConfig(connectionString);
          final request = QueryRequest(
            id: 'req-long-preview',
            agentId: config.agentId,
            query: sql,
            timestamp: DateTime.now(),
            expectMultipleResults: true,
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledConnectionId);
          });
          when(
            () => mockService.executeQueryMultiFull(
              pooledConnectionId,
              any(),
            ),
          ).thenAnswer((_) async {
            return const Success(QueryResultMulti(items: []));
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: directConnectionId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(
            () => mockService.executeQueryMultiFull(
              directConnectionId,
              any(),
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResultMulti(
                items: [
                  QueryResultMultiItem.resultSet(
                    QueryResult(
                      columns: ['a'],
                      rows: [
                        [1],
                      ],
                      rowCount: 1,
                    ),
                  ),
                  QueryResultMultiItem.resultSet(
                    QueryResult(
                      columns: ['b'],
                      rows: [
                        [2],
                      ],
                      rowCount: 1,
                    ),
                  ),
                ],
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer(
            (_) async => const Success(unit),
          );
          when(() => mockService.disconnect(directConnectionId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          final result = await gateway.executeQuery(request);

          expect(result.isSuccess(), isTrue);
          verify(
            () => mockService.executeQueryMultiFull(directConnectionId, sql),
          ).called(1);
        },
      );

      test(
        'should use executeQueryNamed when request has parameters',
        () async {
          const pooledId = 'pool-named';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final request = QueryRequest(
            id: 'req-named',
            agentId: config.agentId,
            query: 'SELECT 1 AS x',
            parameters: <String, dynamic>{'p': 1},
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQueryNamed(
              pooledId,
              any(),
              any(),
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          final result = await gateway.executeQuery(request);

          expect(result.isSuccess(), isTrue);
          verify(
            () => mockService.executeQueryNamed(
              pooledId,
              any(),
              any(),
            ),
          ).called(1);
          verifyNever(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          );
        },
      );

      test(
        'should fallback to direct when pooled returns ConnectionError code 100000',
        () async {
          const pooledId = 'pool-ce1';
          const directId = 'direct-ce1';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final request = QueryRequest(
            id: 'req-ce1',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              ConnectionError(
                message: 'stale handle',
                nativeCode: 100000,
              ),
            );
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: directId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: directId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockService.disconnect(directId)).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeQuery(request);

          expect(result.isSuccess(), isTrue);
          verify(() => mockService.disconnect(directId)).called(1);
        },
      );

      test(
        'should fallback to direct when pooled returns ValidationError for invalid connection id',
        () async {
          const pooledId = 'pool-ve';
          const directId = 'direct-ve';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final request = QueryRequest(
            id: 'req-ve',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              ValidationError(
                message: 'invalid connection id for pooled handle',
              ),
            );
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: directId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: directId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockService.disconnect(directId)).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeQuery(request);

          expect(result.isSuccess(), isTrue);
        },
      );

      test(
        'should fallback to direct when ConnectionError message mentions invalid connection id',
        () async {
          const pooledId = 'pool-ce-msg';
          const directId = 'direct-ce-msg';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final request = QueryRequest(
            id: 'req-ce-msg',
            agentId: config.agentId,
            query: 'SELECT 1',
            timestamp: DateTime.now(),
          );

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              ConnectionError(
                message: 'driver says invalid connection id',
                nativeCode: 1,
              ),
            );
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: directId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: directId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockService.disconnect(directId)).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeQuery(request);

          expect(result.isSuccess(), isTrue);
        },
      );
    });

    group('executeNonQuery direct fallback', () {
      test(
        'should map connection failure when direct connect fails after invalid pool id',
        () async {
          const pooledId = 'pool-nq-inv';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              QueryError(message: 'invalid connection id'),
            );
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return const Failure(QueryError(message: 'direct login failed'));
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeNonQuery('SELECT 1', null);

          expect(result.isError(), isTrue);
          expect(result.exceptionOrNull(), isA<domain.ConnectionFailure>());
        },
      );

      test(
        'should map SQL timeout on direct path after invalid pool id',
        () async {
          const pooledId = 'pool-nq-inv-to';
          const directId = 'direct-nq-inv-to';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              QueryError(message: 'invalid connection id'),
            );
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: directId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: directId,
            ),
          ).thenAnswer((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 400));
            return const Success(
              QueryResult(columns: [], rows: [], rowCount: 0),
            );
          });
          when(() => mockService.disconnect(directId)).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeNonQuery(
            'UPDATE t SET x=1',
            null,
            timeout: const Duration(milliseconds: 40),
          );

          expect(result.isError(), isTrue);
          expect(
            result.exceptionOrNull(),
            isA<domain.QueryExecutionFailure>(),
          );
          verify(() => mockService.disconnect(directId)).called(2);
        },
      );

      test(
        'should map query failure on direct path after invalid pool id',
        () async {
          const pooledId = 'pool-nq-inv-qf';
          const directId = 'direct-nq-inv-qf';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              QueryError(message: 'invalid connection id'),
            );
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: directId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: directId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              QueryError(message: 'direct non-query failed'),
            );
          });
          when(() => mockService.disconnect(directId)).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeNonQuery(
            'UPDATE t SET x=1',
            null,
          );

          expect(result.isError(), isTrue);
          expect(
            result.exceptionOrNull(),
            isA<domain.QueryExecutionFailure>(),
          );
        },
      );

      test(
        'should complete when pool recycle fails after invalid pool id',
        () async {
          const pooledId = 'pool-nq-rec-fail';
          const directId = 'direct-nq-rec-fail';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Failure(
              QueryError(message: 'invalid connection id'),
            );
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: directId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: directId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(columns: [], rows: [], rowCount: 0),
            );
          });
          when(() => mockService.disconnect(directId)).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return Failure(
              domain.ConnectionFailure('recycle failed'),
            );
          });

          final result = await gateway.executeNonQuery(
            'UPDATE t SET x=1',
            null,
          );

          expect(result.isSuccess(), isTrue);
        },
      );
    });

    group('executeBatch extended', () {
      test(
        'executeBatch should fail when ODBC init fails before batch context',
        () async {
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Failure(
              QueryError(message: 'ODBC init failed for batch'),
            );
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [SqlCommand(sql: 'SELECT 1')],
          );

          expect(result.isError(), isTrue);
          verifyNever(() => mockConfigRepository.getCurrentConfig());
        },
      );

      test(
        'executeBatch should fail when config repository fails for batch',
        () async {
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Failure(domain.NotFoundFailure('no config'));
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [SqlCommand(sql: 'SELECT 1')],
          );

          expect(result.isError(), isTrue);
          final failure =
              result.exceptionOrNull()! as domain.ConfigurationFailure;
          expect(
            failure.message,
            'Failed to load database configuration for batch execution',
          );
          verifyNever(() => mockConnectionPool.acquire(any()));
        },
      );

      test(
        'non-transactional batch should record per-command validation failure',
        () async {
          const pooledId = 'pool-batch-val';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['id'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [
              SqlCommand(sql: 'SELECT 1'),
              SqlCommand(sql: ''),
            ],
          );

          expect(result.isSuccess(), isTrue);
          final items = result.getOrNull()!;
          expect(items, hasLength(2));
          expect(items[0].ok, isTrue);
          expect(items[1].ok, isFalse);
          expect(items[1].error, isNotNull);
        },
      );

      test(
        'non-transactional batch should record per-command query failure',
        () async {
          const pooledId = 'pool-batch-qfail';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          var execCalls = 0;

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            execCalls++;
            if (execCalls == 1) {
              return const Success(
                QueryResult(
                  columns: ['id'],
                  rows: [
                    [1],
                  ],
                  rowCount: 1,
                ),
              );
            }
            return const Failure(QueryError(message: 'batch item failed'));
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [
              SqlCommand(sql: 'SELECT 1'),
              SqlCommand(sql: 'SELECT 2'),
            ],
          );

          expect(result.isSuccess(), isTrue);
          final items = result.getOrNull()!;
          expect(items, hasLength(2));
          expect(items[0].ok, isTrue);
          expect(items[1].ok, isFalse);
          expect(items[1].error, contains('batch item failed'));
        },
      );

      test(
        'non-transactional read-only batch should use multi-result fast-path',
        () async {
          const pooledId = 'pool-batch-multi';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQueryMultiFull(
              pooledId,
              any(),
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResultMulti(
                items: [
                  QueryResultMultiItem.resultSet(
                    QueryResult(
                      columns: ['a'],
                      rows: [
                        [1],
                        [2],
                      ],
                      rowCount: 2,
                    ),
                  ),
                  QueryResultMultiItem.resultSet(
                    QueryResult(
                      columns: ['b'],
                      rows: [
                        [3],
                      ],
                      rowCount: 1,
                    ),
                  ),
                ],
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [
              SqlCommand(sql: 'SELECT a FROM t ORDER BY a'),
              SqlCommand(sql: 'SELECT b FROM t ORDER BY b'),
            ],
            options: const SqlExecutionOptions(maxRows: 1),
          );

          expect(result.isSuccess(), isTrue);
          final items = result.getOrNull()!;
          expect(items, hasLength(2));
          expect(items[0].rows, [
            {'a': 1},
          ]);
          expect(items[1].rows, [
            {'b': 3},
          ]);
          verify(
            () => mockService.executeQueryMultiFull(pooledId, any()),
          ).called(
            1,
          );
          verifyNever(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          );
        },
      );

      test(
        'non-transactional read-only batch should fallback when multi-result '
        'payload is incomplete',
        () async {
          const pooledId = 'pool-batch-fallback';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          var executeQueryCalls = 0;

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQueryMultiFull(
              pooledId,
              any(),
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResultMulti(
                items: [
                  QueryResultMultiItem.resultSet(
                    QueryResult(
                      columns: ['only_one'],
                      rows: [
                        [1],
                      ],
                      rowCount: 1,
                    ),
                  ),
                ],
              ),
            );
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            executeQueryCalls++;
            return Success(
              QueryResult(
                columns: ['value'],
                rows: [
                  [executeQueryCalls],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [
              SqlCommand(sql: 'SELECT 1 AS value'),
              SqlCommand(sql: 'SELECT 2 AS value'),
            ],
          );

          expect(result.isSuccess(), isTrue);
          final items = result.getOrNull()!;
          expect(items, hasLength(2));
          expect(items[0].rows, [
            {'value': 1},
          ]);
          expect(items[1].rows, [
            {'value': 2},
          ]);
          verify(
            () => mockService.executeQueryMultiFull(pooledId, any()),
          ).called(
            1,
          );
          verify(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).called(2);
        },
      );

      test(
        'transactional batch should abort and rollback on validation failure',
        () async {
          const ownedId = 'owned-tx-val';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: ownedId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(() => mockService.beginTransaction(ownedId)).thenAnswer((
            _,
          ) async {
            return const Success(77);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: ownedId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['id'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockService.rollbackTransaction(ownedId, 77)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [
              SqlCommand(sql: 'SELECT 1'),
              SqlCommand(sql: ''),
            ],
            options: const SqlExecutionOptions(transaction: true),
          );

          expect(result.isError(), isTrue);
          verify(
            () => mockService.rollbackTransaction(ownedId, 77),
          ).called(1);
          verifyNever(
            () => mockService.commitTransaction(ownedId, any()),
          );
        },
      );

      test(
        'transactional batch should abort and rollback on command execution failure',
        () async {
          const ownedId = 'owned-tx-ex';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: ownedId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(() => mockService.beginTransaction(ownedId)).thenAnswer((
            _,
          ) async {
            return const Success(5);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: ownedId,
            ),
          ).thenAnswer((_) async {
            return const Failure(QueryError(message: 'deadlock'));
          });
          when(() => mockService.rollbackTransaction(ownedId, 5)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [SqlCommand(sql: 'SELECT 1')],
            options: const SqlExecutionOptions(transaction: true),
          );

          expect(result.isError(), isTrue);
          verify(
            () => mockService.rollbackTransaction(ownedId, 5),
          ).called(1);
        },
      );

      test(
        'transactional batch should rollback when commit fails',
        () async {
          const ownedId = 'owned-tx-commit-fail';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: ownedId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(() => mockService.beginTransaction(ownedId)).thenAnswer((
            _,
          ) async {
            return const Success(10);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: ownedId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['id'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockService.commitTransaction(ownedId, 10)).thenAnswer((
            _,
          ) async {
            return const Failure(QueryError(message: 'commit failed'));
          });
          when(() => mockService.rollbackTransaction(ownedId, 10)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [SqlCommand(sql: 'SELECT 1')],
            options: const SqlExecutionOptions(transaction: true),
          );

          expect(result.isError(), isTrue);
          verify(
            () => mockService.rollbackTransaction(ownedId, 10),
          ).called(1);
        },
      );

      test(
        'transactional batch should record rollback failure when rollback fails after commit fails',
        () async {
          const ownedId = 'owned-tx-rb-fail';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          final prior = metrics.transactionRollbackFailureCount;

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: ownedId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(() => mockService.beginTransaction(ownedId)).thenAnswer((
            _,
          ) async {
            return const Success(11);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: ownedId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['id'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockService.commitTransaction(ownedId, 11)).thenAnswer((
            _,
          ) async {
            return const Failure(QueryError(message: 'commit failed'));
          });
          when(() => mockService.rollbackTransaction(ownedId, 11)).thenAnswer((
            _,
          ) async {
            return const Failure(QueryError(message: 'rollback failed'));
          });
          when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [SqlCommand(sql: 'SELECT 1')],
            options: const SqlExecutionOptions(transaction: true),
          );

          expect(result.isError(), isTrue);
          verify(
            () => mockService.rollbackTransaction(ownedId, 11),
          ).called(1);
          expect(
            metrics.transactionRollbackFailureCount,
            greaterThan(prior),
          );
        },
      );

      test(
        'transactional batch should fail when direct connect fails',
        () async {
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return const Failure(QueryError(message: 'login failed'));
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [SqlCommand(sql: 'SELECT 1')],
            options: const SqlExecutionOptions(transaction: true),
          );

          expect(result.isError(), isTrue);
          expect(result.exceptionOrNull(), isA<domain.ConnectionFailure>());
        },
      );

      test(
        'transactional batch should fail when beginTransaction fails',
        () async {
          const ownedId = 'owned-tx-begin-fail';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: ownedId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(() => mockService.beginTransaction(ownedId)).thenAnswer((
            _,
          ) async {
            return const Failure(QueryError(message: 'cannot begin tx'));
          });
          when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [SqlCommand(sql: 'SELECT 1')],
            options: const SqlExecutionOptions(transaction: true),
          );

          expect(result.isError(), isTrue);
          verifyNever(
            () => mockService.rollbackTransaction(ownedId, any()),
          );
        },
      );

      test(
        'transactional batch should retry after invalid connection id on begin',
        () async {
          const ownedA = 'owned-tx-retry-a';
          const ownedB = 'owned-tx-retry-b';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);
          var connectCall = 0;

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            connectCall++;
            final id = connectCall == 1 ? ownedA : ownedB;
            return Success(
              Connection(
                id: id,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(() => mockService.beginTransaction(ownedA)).thenAnswer((
            _,
          ) async {
            return const Failure(
              QueryError(message: 'invalid connection id for handle'),
            );
          });
          when(() => mockService.beginTransaction(ownedB)).thenAnswer((
            _,
          ) async {
            return const Success(2);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: ownedB,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['id'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockService.commitTransaction(ownedB, 2)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockService.disconnect(ownedA)).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockService.disconnect(ownedB)).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [SqlCommand(sql: 'SELECT 1')],
            options: const SqlExecutionOptions(transaction: true),
          );

          expect(result.isSuccess(), isTrue);
          verify(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).called(2);
        },
      );

      test(
        'non-transactional pooled batch should fail with SQL timeout',
        () async {
          const pooledId = 'pool-batch-to';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockService.disconnect(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [SqlCommand(sql: 'SELECT 1')],
            timeout: const Duration(milliseconds: 40),
          );

          expect(result.isError(), isTrue);
          final failure =
              result.exceptionOrNull()! as domain.QueryExecutionFailure;
          expect(failure.message, contains('Batch SQL execution timeout'));
        },
      );

      test(
        'transactional batch should abort on SQL timeout',
        () async {
          const ownedId = 'owned-batch-to';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(
            () => mockService.connect(any(), options: any(named: 'options')),
          ).thenAnswer((_) async {
            return Success(
              Connection(
                id: ownedId,
                connectionString: connectionString,
                createdAt: DateTime.now(),
                isActive: true,
              ),
            );
          });
          when(() => mockService.beginTransaction(ownedId)).thenAnswer((
            _,
          ) async {
            return const Success(3);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: ownedId,
            ),
          ).thenAnswer((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return const Success(
              QueryResult(
                columns: ['x'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockService.rollbackTransaction(ownedId, 3)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });
          when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
            return const Success(unit);
          });

          final result = await gateway.executeBatch(
            config.agentId,
            const [SqlCommand(sql: 'SELECT 1')],
            options: const SqlExecutionOptions(transaction: true),
            timeout: const Duration(milliseconds: 40),
          );

          expect(result.isError(), isTrue);
          verify(
            () => mockService.rollbackTransaction(ownedId, 3),
          ).called(1);
        },
      );

      test(
        'should throw TimeoutException when batch deadline is already expired',
        () async {
          const pooledId = 'pool-batch-deadline';
          const connectionString = 'Driver={ODBC Driver};Server=localhost;';
          final config = _buildConfig(connectionString);

          when(() => mockService.initialize()).thenAnswer((_) async {
            return const Success(unit);
          });
          when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
            _,
          ) async {
            return Success(config);
          });
          when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
            return const Success(pooledId);
          });
          when(
            () => mockService.executeQuery(
              any(),
              connectionId: pooledId,
            ),
          ).thenAnswer((_) async {
            return const Success(
              QueryResult(
                columns: ['id'],
                rows: [
                  [1],
                ],
                rowCount: 1,
              ),
            );
          });
          when(() => mockConnectionPool.release(pooledId)).thenAnswer((
            _,
          ) async {
            return const Success(unit);
          });

          await expectLater(
            gateway.executeBatch(
              config.agentId,
              const [SqlCommand(sql: 'SELECT 1')],
              timeout: Duration.zero,
            ),
            throwsA(isA<TimeoutException>()),
          );
        },
      );
    });

    test(
      'should fallback to direct connection on invalid pooled connection id',
      () async {
        const pooledConnectionId = '100000';
        const directConnectionId = 'direct-1';
        const sql = 'SELECT * FROM users';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-1',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: pooledConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Failure(
            ValidationError(message: 'Invalid connection ID: 100000'),
          );
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: directConnectionId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: directConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(
              columns: ['id'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          );
        });
        when(() => mockService.disconnect(directConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.recycle(any())).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        verify(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).called(1);
        verify(() => mockService.disconnect(directConnectionId)).called(1);
        verify(() => mockConnectionPool.release(pooledConnectionId)).called(1);
        verify(() => mockConnectionPool.recycle(any())).called(1);
      },
    );

    test('should keep success even when pool release fails', () async {
      const pooledConnectionId = 'pool-1';
      const sql = 'SELECT * FROM users';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      final config = _buildConfig(connectionString);
      final request = QueryRequest(
        id: 'req-2',
        agentId: config.agentId,
        query: sql,
        timestamp: DateTime.now(),
      );

      when(() => mockService.initialize()).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((_) async {
        return Success(config);
      });
      when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
        return const Success(pooledConnectionId);
      });
      when(
        () => mockService.executeQuery(
          any(),
          connectionId: pooledConnectionId,
        ),
      ).thenAnswer((_) async {
        return const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [1],
            ],
            rowCount: 1,
          ),
        );
      });
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
        _,
      ) async {
        return Failure(Exception('release failed'));
      });

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      verify(() => mockConnectionPool.release(pooledConnectionId)).called(1);
      expect(metrics.connectionPoolReleaseFailureCount, 1);
    });

    test(
      'should fail executeQuery when pool acquire fails and record pool metric',
      () async {
        const sql = 'SELECT 1';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-acquire-fail',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return Failure(Exception('pool exhausted'));
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        // Default retry manager runs up to 3 attempts; each calls acquire.
        expect(metrics.connectionPoolAcquireFailureCount, 3);
        verifyNever(() => mockConnectionPool.release(any()));
      },
    );

    test(
      'should retry with expanded buffer when pooled query buffer is too small',
      () async {
        const pooledConnectionId = 'pool-buffer';
        const directConnectionId = 'direct-buffer';
        const sql = 'SELECT * FROM very_large_table';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-buffer',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: pooledConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Failure(
            QueryError(
              message: 'Buffer too small: need 60830894 bytes, got 33554432',
            ),
          );
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: directConnectionId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: directConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(
              columns: ['id'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          );
        });
        when(() => mockService.disconnect(directConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        verify(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).called(1);
        verify(() => mockService.disconnect(directConnectionId)).called(1);
        verify(() => mockConnectionPool.release(pooledConnectionId)).called(1);
      },
    );

    test('should apply SQL Server pagination and expose hasNextPage', () async {
      const pooledConnectionId = 'pool-page';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      final config = _buildConfig(connectionString);
      final request = QueryRequest(
        id: 'req-page',
        agentId: config.agentId,
        query: 'SELECT * FROM users ORDER BY id',
        timestamp: DateTime.now(),
        pagination: const QueryPaginationRequest(
          page: 2,
          pageSize: 2,
          queryHash: 'query-hash',
          orderBy: [
            QueryPaginationOrderTerm(
              expression: 'id',
              lookupKey: 'id',
            ),
          ],
        ),
      );

      when(() => mockService.initialize()).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((_) async {
        return Success(config);
      });
      when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
        return const Success(pooledConnectionId);
      });
      when(
        () => mockService.executeQuery(
          any(),
          connectionId: pooledConnectionId,
        ),
      ).thenAnswer((_) async {
        return const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [3],
              [4],
              [5],
            ],
            rowCount: 3,
          ),
        );
      });
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
        _,
      ) async {
        return const Success(unit);
      });

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      final response = result.getOrNull()!;
      expect(response.data, hasLength(2));
      expect(response.pagination, isNotNull);
      expect(response.pagination!.page, 2);
      expect(response.pagination!.hasNextPage, isTrue);
      expect(response.pagination!.nextCursor, isNotNull);
      final capturedSql =
          verify(
                () => mockService.executeQuery(
                  captureAny(),
                  connectionId: pooledConnectionId,
                ),
              ).captured.single
              as String;
      expect(capturedSql, contains('OFFSET 2 ROWS'));
      expect(capturedSql, contains('FETCH NEXT 3 ROWS ONLY'));
      expect(capturedSql, contains('ORDER BY id ASC'));
    });

    test(
      'should apply SQL Anywhere offset pagination with TOP START AT syntax',
      () async {
        const pooledConnectionId = 'pool-sa-page';
        const connectionString = 'Driver={SQL Anywhere 17};Server=localhost;';
        final config = _buildConfig(
          connectionString,
          driverName: 'SQL Anywhere',
          odbcDriverName: 'SQL Anywhere 17',
        );
        final request = QueryRequest(
          id: 'req-sa-page',
          agentId: config.agentId,
          query: 'SELECT * FROM produto ORDER BY CodProduto',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 2,
            pageSize: 2,
            queryHash: 'query-hash',
            orderBy: [
              QueryPaginationOrderTerm(
                expression: 'CodProduto',
                lookupKey: 'CodProduto',
              ),
            ],
          ),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: pooledConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(
              columns: ['CodProduto'],
              rows: [
                [3],
                [4],
                [5],
              ],
              rowCount: 3,
            ),
          );
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        final capturedSql =
            verify(
                  () => mockService.executeQuery(
                    captureAny(),
                    connectionId: pooledConnectionId,
                  ),
                ).captured.single
                as String;
        expect(capturedSql, contains('TOP 3 START AT 3'));
        expect(capturedSql, isNot(contains('OFFSET')));
        expect(capturedSql, isNot(contains('FETCH NEXT')));
        expect(capturedSql, contains('ORDER BY CodProduto ASC'));
      },
    );

    test(
      'should reject SQL Server pagination without explicit order by terms',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-page-no-order',
          agentId: config.agentId,
          query: 'SELECT * FROM users',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 1,
            pageSize: 10,
          ),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        if (failure case final domain.ValidationFailure validationFailure) {
          expect(
            validationFailure.message,
            contains('requires an explicit ORDER BY'),
          );
        } else {
          fail('Expected ValidationFailure');
        }
        verifyNever(() => mockConnectionPool.acquire(any()));
      },
    );

    test(
      'should reject SQL Anywhere pagination without explicit order by terms',
      () async {
        const connectionString = 'Driver={SQL Anywhere 17};Server=localhost;';
        final config = _buildConfig(
          connectionString,
          driverName: 'SQL Anywhere',
          odbcDriverName: 'SQL Anywhere 17',
        );
        final request = QueryRequest(
          id: 'req-anywhere-page-no-order',
          agentId: config.agentId,
          query: 'SELECT * FROM users',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 1,
            pageSize: 10,
          ),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        if (failure case final domain.ValidationFailure validationFailure) {
          expect(
            validationFailure.message,
            contains('requires an explicit ORDER BY'),
          );
        } else {
          fail('Expected ValidationFailure');
        }
        verifyNever(() => mockConnectionPool.acquire(any()));
      },
    );

    test(
      'should reject preserve_sql combined with managed pagination in gateway',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-preserve-sql-pagination',
          agentId: config.agentId,
          query: 'SELECT * FROM users ORDER BY id',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 1,
            pageSize: 10,
            orderBy: [
              QueryPaginationOrderTerm(
                expression: 'id',
                lookupKey: 'id',
              ),
            ],
          ),
          sqlHandlingMode: SqlHandlingMode.preserve,
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        if (failure case final domain.ValidationFailure validationFailure) {
          expect(
            validationFailure.message,
            contains('preserve_sql cannot be combined with managed pagination'),
          );
        } else {
          fail('Expected ValidationFailure');
        }
        verifyNever(() => mockConnectionPool.acquire(any()));
      },
    );

    test('should apply PostgreSQL pagination syntax', () async {
      const pooledConnectionId = 'pool-pg';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      final config = _buildConfig(
        connectionString,
        driverName: 'PostgreSQL',
        odbcDriverName: 'PostgreSQL Unicode',
      );
      final request = QueryRequest(
        id: 'req-pg',
        agentId: config.agentId,
        query: 'SELECT * FROM users ORDER BY id',
        timestamp: DateTime.now(),
        pagination: const QueryPaginationRequest(
          page: 1,
          pageSize: 10,
          queryHash: 'query-hash',
          orderBy: [
            QueryPaginationOrderTerm(
              expression: 'id',
              lookupKey: 'id',
            ),
          ],
        ),
      );

      when(() => mockService.initialize()).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((_) async {
        return Success(config);
      });
      when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
        return const Success(pooledConnectionId);
      });
      when(
        () => mockService.executeQuery(
          any(),
          connectionId: pooledConnectionId,
        ),
      ).thenAnswer((_) async {
        return const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [1],
            ],
            rowCount: 1,
          ),
        );
      });
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
        _,
      ) async {
        return const Success(unit);
      });

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      final capturedSql =
          verify(
                () => mockService.executeQuery(
                  captureAny(),
                  connectionId: pooledConnectionId,
                ),
              ).captured.single
              as String;
      expect(capturedSql, contains('ORDER BY id ASC'));
      expect(capturedSql, contains('LIMIT 11 OFFSET 0'));
    });

    test(
      'should allow PostgreSQL pagination without explicit order by terms',
      () async {
        const pooledConnectionId = 'pool-pg-no-order';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(
          connectionString,
          driverName: 'PostgreSQL',
          odbcDriverName: 'PostgreSQL Unicode',
        );
        final request = QueryRequest(
          id: 'req-pg-no-order',
          agentId: config.agentId,
          query: 'SELECT * FROM users',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 1,
            pageSize: 10,
          ),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: pooledConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(
              columns: ['id'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          );
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        final capturedSql =
            verify(
                  () => mockService.executeQuery(
                    captureAny(),
                    connectionId: pooledConnectionId,
                  ),
                ).captured.single
                as String;
        expect(capturedSql, contains('LIMIT 11 OFFSET 0'));
        expect(capturedSql, isNot(contains('ORDER BY')));
      },
    );

    test(
      'should reject SQL that already declares pagination clauses when options pagination is active',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-sql-has-limit',
          agentId: config.agentId,
          query: 'SELECT * FROM users LIMIT 10',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 1,
            pageSize: 10,
          ),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull();
        if (failure case final domain.ValidationFailure validationFailure) {
          expect(
            validationFailure.message,
            contains('cannot include LIMIT/OFFSET/FETCH'),
          );
        } else {
          fail('Expected ValidationFailure');
        }
        verifyNever(() => mockConnectionPool.acquire(any()));
      },
    );

    test(
      'should prefer persisted connection string instead of rebuilding one',
      () async {
        const persistedConnectionString =
            'DSN=PersistedConnection;Encrypt=yes;';
        final config = _buildConfig(persistedConnectionString);
        final request = QueryRequest(
          id: 'req-conn-string',
          agentId: config.agentId,
          query: 'SELECT 1',
          timestamp: DateTime.now(),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return const Success('pool-1');
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: 'pool-1',
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(
              columns: ['value'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          );
        });
        when(() => mockConnectionPool.release('pool-1')).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        verify(
          () => mockConnectionPool.acquire(persistedConnectionString),
        ).called(1);
      },
    );

    test('should apply keyset cursor pagination syntax', () async {
      const pooledConnectionId = 'pool-cursor';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      final config = _buildConfig(connectionString);
      final request = QueryRequest(
        id: 'req-cursor',
        agentId: config.agentId,
        query: 'SELECT * FROM users ORDER BY id',
        timestamp: DateTime.now(),
        pagination: const QueryPaginationRequest(
          page: 2,
          pageSize: 2,
          cursor: 'cursor-1',
          queryHash: 'query-hash',
          orderBy: [
            QueryPaginationOrderTerm(
              expression: 'id',
              lookupKey: 'id',
            ),
          ],
          lastRowValues: [2],
        ),
      );

      when(() => mockService.initialize()).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((_) async {
        return Success(config);
      });
      when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
        return const Success(pooledConnectionId);
      });
      when(
        () => mockService.executeQuery(
          any(),
          connectionId: pooledConnectionId,
        ),
      ).thenAnswer((_) async {
        return const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [3],
              [4],
              [5],
            ],
            rowCount: 3,
          ),
        );
      });
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
        _,
      ) async {
        return const Success(unit);
      });

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      final capturedSql =
          verify(
                () => mockService.executeQuery(
                  captureAny(),
                  connectionId: pooledConnectionId,
                ),
              ).captured.single
              as String;
      expect(capturedSql, contains('WHERE (id > 2)'));
      expect(capturedSql, contains('ORDER BY id ASC'));
      expect(capturedSql, contains('FETCH NEXT 3 ROWS ONLY'));
    });

    test(
      'should apply SQL Anywhere keyset cursor pagination with TOP syntax',
      () async {
        const pooledConnectionId = 'pool-sa-cursor';
        const connectionString = 'Driver={SQL Anywhere 17};Server=localhost;';
        final config = _buildConfig(
          connectionString,
          driverName: 'SQL Anywhere',
          odbcDriverName: 'SQL Anywhere 17',
        );
        final request = QueryRequest(
          id: 'req-sa-cursor',
          agentId: config.agentId,
          query: 'SELECT * FROM users ORDER BY id',
          timestamp: DateTime.now(),
          pagination: const QueryPaginationRequest(
            page: 2,
            pageSize: 2,
            cursor: 'cursor-1',
            queryHash: 'query-hash',
            orderBy: [
              QueryPaginationOrderTerm(
                expression: 'id',
                lookupKey: 'id',
              ),
            ],
            lastRowValues: [2],
          ),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: pooledConnectionId,
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(
              columns: ['id'],
              rows: [
                [3],
                [4],
                [5],
              ],
              rowCount: 3,
            ),
          );
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        final capturedSql =
            verify(
                  () => mockService.executeQuery(
                    captureAny(),
                    connectionId: pooledConnectionId,
                  ),
                ).captured.single
                as String;
        expect(capturedSql, contains('TOP 3'));
        expect(capturedSql, contains('WHERE (id > 2)'));
        expect(capturedSql, contains('ORDER BY id ASC'));
        expect(capturedSql, isNot(contains('OFFSET')));
        expect(capturedSql, isNot(contains('FETCH NEXT')));
      },
    );

    test('should map multiple result sets and row counts', () async {
      const pooledConnectionId = 'pool-multi';
      const connectionString = 'Driver={ODBC Driver};Server=localhost;';
      final config = _buildConfig(connectionString);
      final request = QueryRequest(
        id: 'req-multi',
        agentId: config.agentId,
        query:
            'SELECT 1 AS first_value; UPDATE users SET active = 1; SELECT 2 AS second_value;',
        timestamp: DateTime.now(),
        expectMultipleResults: true,
      );

      when(() => mockService.initialize()).thenAnswer((_) async {
        return const Success(unit);
      });
      when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((_) async {
        return Success(config);
      });
      when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
        return const Success(pooledConnectionId);
      });
      when(
        () => mockService.executeQueryMultiFull(
          pooledConnectionId,
          any(),
        ),
      ).thenAnswer((_) async {
        return const Success(
          QueryResultMulti(
            items: [
              QueryResultMultiItem.resultSet(
                QueryResult(
                  columns: ['first_value'],
                  rows: [
                    [1],
                  ],
                  rowCount: 1,
                ),
              ),
              QueryResultMultiItem.rowCount(3),
              QueryResultMultiItem.resultSet(
                QueryResult(
                  columns: ['second_value'],
                  rows: [
                    [2],
                  ],
                  rowCount: 1,
                ),
              ),
            ],
          ),
        );
      });
      when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
        _,
      ) async {
        return const Success(unit);
      });

      final result = await gateway.executeQuery(request);

      expect(result.isSuccess(), isTrue);
      final response = result.getOrNull()!;
      expect(response.data.single['first_value'], 1);
      expect(response.resultSets, hasLength(2));
      expect(response.items, hasLength(3));
      expect(response.items[1].rowCount, 3);
      expect(response.columnMetadata, [
        {'name': 'first_value'},
      ]);
      verify(
        () => mockService.executeQueryMultiFull(
          pooledConnectionId,
          request.query,
        ),
      ).called(1);
    });

    test(
      'should fallback to direct connection when pooled multi-result is vacuous',
      () async {
        const pooledConnectionId = 'pool-multi-empty';
        const directConnectionId = 'direct-multi';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const sql = 'SELECT 1 AS a; SELECT 2 AS b;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-multi-fallback',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
          expectMultipleResults: true,
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeQueryMultiFull(
            pooledConnectionId,
            any(),
          ),
        ).thenAnswer((_) async {
          return const Success(QueryResultMulti(items: []));
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: directConnectionId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(
          () => mockService.executeQueryMultiFull(
            directConnectionId,
            any(),
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResultMulti(
              items: [
                QueryResultMultiItem.resultSet(
                  QueryResult(
                    columns: ['a'],
                    rows: [
                      [1],
                    ],
                    rowCount: 1,
                  ),
                ),
                QueryResultMultiItem.resultSet(
                  QueryResult(
                    columns: ['b'],
                    rows: [
                      [2],
                    ],
                    rowCount: 1,
                  ),
                ),
              ],
            ),
          );
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(directConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        final response = result.getOrNull()!;
        expect(response.resultSets, hasLength(2));
        expect(response.data.single['a'], 1);
        verify(
          () => mockService.executeQueryMultiFull(pooledConnectionId, sql),
        ).called(1);
        verify(
          () => mockService.executeQueryMultiFull(directConnectionId, sql),
        ).called(1);
        verify(() => mockService.disconnect(directConnectionId)).called(1);
        expect(metrics.multiResultPoolVacuousFallbackCount, 1);
        expect(metrics.multiResultDirectStillVacuousCount, 0);
      },
    );

    test(
      'should record direct-still-vacuous when pool and direct multi are empty',
      () async {
        const pooledConnectionId = 'pool-multi-empty-twice';
        const directConnectionId = 'direct-multi-empty';
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const sql = 'SELECT 1 AS a; SELECT 2 AS b;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-multi-empty-both',
          agentId: config.agentId,
          query: sql,
          timestamp: DateTime.now(),
          expectMultipleResults: true,
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(() => mockConnectionPool.acquire(any())).thenAnswer((_) async {
          return const Success(pooledConnectionId);
        });
        when(
          () => mockService.executeQueryMultiFull(
            pooledConnectionId,
            any(),
          ),
        ).thenAnswer((_) async {
          return const Success(QueryResultMulti(items: []));
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: directConnectionId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(
          () => mockService.executeQueryMultiFull(
            directConnectionId,
            any(),
          ),
        ).thenAnswer((_) async {
          return const Success(QueryResultMulti(items: []));
        });
        when(() => mockConnectionPool.release(pooledConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(directConnectionId)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isSuccess(), isTrue);
        final response = result.getOrNull()!;
        expect(response.resultSets, isEmpty);
        expect(metrics.multiResultPoolVacuousFallbackCount, 1);
        expect(metrics.multiResultDirectStillVacuousCount, 1);
      },
    );

    test(
      'should use direct ODBC connection for transactional executeBatch',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        const ownedId = 'owned-tx-1';
        final config = _buildConfig(connectionString);

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });
        when(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).thenAnswer((_) async {
          return Success(
            Connection(
              id: ownedId,
              connectionString: connectionString,
              createdAt: DateTime.now(),
              isActive: true,
            ),
          );
        });
        when(() => mockService.beginTransaction(ownedId)).thenAnswer((
          _,
        ) async {
          return const Success(1);
        });
        when(
          () => mockService.executeQuery(
            any(),
            connectionId: ownedId,
          ),
        ).thenAnswer((_) async {
          return const Success(
            QueryResult(
              columns: ['id'],
              rows: [
                [1],
              ],
              rowCount: 1,
            ),
          );
        });
        when(() => mockService.commitTransaction(ownedId, 1)).thenAnswer((
          _,
        ) async {
          return const Success(unit);
        });
        when(() => mockService.disconnect(ownedId)).thenAnswer((_) async {
          return const Success(unit);
        });

        final result = await gateway.executeBatch(
          config.agentId,
          const [SqlCommand(sql: 'SELECT 1')],
          options: const SqlExecutionOptions(transaction: true),
        );

        expect(result.isSuccess(), isTrue);
        verifyNever(() => mockConnectionPool.acquire(any()));
        verify(
          () => mockService.connect(any(), options: any(named: 'options')),
        ).called(1);
        verify(() => mockService.disconnect(ownedId)).called(1);
        expect(metrics.transactionalBatchDirectPathCount, 1);
      },
    );

    test(
      'should reject multi-result request with pagination before pool acquire',
      () async {
        const connectionString = 'Driver={ODBC Driver};Server=localhost;';
        final config = _buildConfig(connectionString);
        final request = QueryRequest(
          id: 'req-multi-page',
          agentId: config.agentId,
          query: 'SELECT 1 AS id; SELECT 2 AS id;',
          timestamp: DateTime.now(),
          expectMultipleResults: true,
          pagination: const QueryPaginationRequest(
            page: 1,
            pageSize: 10,
            orderBy: [
              QueryPaginationOrderTerm(
                expression: 'id',
                lookupKey: 'id',
              ),
            ],
          ),
        );

        when(() => mockService.initialize()).thenAnswer((_) async {
          return const Success(unit);
        });
        when(() => mockConfigRepository.getCurrentConfig()).thenAnswer((
          _,
        ) async {
          return Success(config);
        });

        final result = await gateway.executeQuery(request);

        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(
          failure.message,
          'Multi-result execution cannot be combined with pagination',
        );
        verifyNever(() => mockConnectionPool.acquire(any()));
        verifyNever(
          () => mockService.executeQuery(
            any(),
            connectionId: any(named: 'connectionId'),
          ),
        );
      },
    );
  });
}

Config _buildConfig(
  String connectionString, {
  String driverName = 'SQL Server',
  String odbcDriverName = 'ODBC Driver 17 for SQL Server',
}) {
  final now = DateTime.now();
  return Config(
    id: 'cfg-1',
    driverName: driverName,
    odbcDriverName: odbcDriverName,
    connectionString: connectionString,
    username: 'sa',
    databaseName: 'master',
    host: 'localhost',
    port: 1433,
    createdAt: now,
    updatedAt: now,
    agentId: 'agent-1',
  );
}
