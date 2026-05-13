import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/adaptive_odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class _MockOdbcService extends Mock implements OdbcService {}

class _MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const PoolOptions());
    registerFallbackValue(const ConnectionOptions());
  });

  group('AdaptiveOdbcConnectionPool', () {
    late _MockOdbcService service;
    late _MockAgentConfigRepository configRepository;
    late MockOdbcConnectionSettings settings;
    late FeatureFlags flags;
    late MetricsCollector metrics;

    setUp(() async {
      service = _MockOdbcService();
      configRepository = _MockAgentConfigRepository();
      settings = MockOdbcConnectionSettings();
      flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableOdbcExperimentalDriverAdaptivePooling(true);
      metrics = MetricsCollector()..clear();
    });

    test('routes eligible SQL Server driver through native pool and reports diagnostics', () async {
      when(() => configRepository.getCurrentConfig()).thenAnswer(
        (_) async => Success(_sqlServerConfig()),
      );
      when(
        () => service.poolCreate(
          any(),
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => const Success(41));
      when(() => service.poolGetConnection(41)).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'native-1',
            connectionString: 'DSN=Prod',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(() => service.poolReleaseConnection('native-1')).thenAnswer(
        (_) async => const Success(unit),
      );

      final pool = _buildPool(
        service: service,
        settings: settings,
        flags: flags,
        metrics: metrics,
        configRepository: configRepository,
      );

      final acquired = await pool.acquire('DSN=Prod');
      expect(acquired.getOrNull(), 'native-1');

      final released = await pool.release('native-1');
      expect(released.isSuccess(), isTrue);

      final diagnostics = pool.getHealthDiagnostics();
      expect(diagnostics['strategy'], 'adaptive_experimental');
      expect(diagnostics['effective_strategy'], 'native');
      expect(diagnostics['driver_type'], 'sqlServer');
      expect(diagnostics['native_eligible'], isTrue);
      expect(metrics.odbcNativePoolFallbackCount, 0);
      verify(
        () => service.poolCreate('DSN=Prod;PoolTestOnCheckout=true', any(), options: any(named: 'options')),
      ).called(1);
      verifyNever(() => service.connect(any(), options: any(named: 'options')));
      verify(() => service.poolReleaseConnection('native-1')).called(1);
      verify(() => configRepository.getCurrentConfig()).called(1);
    });

    test('routes to lease pool when custom connection options are required', () async {
      when(() => configRepository.getCurrentConfig()).thenAnswer(
        (_) async => Success(_sqlServerConfig()),
      );
      when(
        () => service.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'lease-options',
            connectionString: 'DSN=Prod',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(() => service.disconnect('lease-options')).thenAnswer(
        (_) async => const Success(unit),
      );

      final pool = _buildPool(
        service: service,
        settings: settings,
        flags: flags,
        metrics: metrics,
        configRepository: configRepository,
      );

      final acquired = await pool.acquire(
        'DSN=Prod',
        options: const ConnectionOptions(
          queryTimeout: Duration(seconds: 5),
          maxResultBufferBytes: 8 * 1024 * 1024,
        ),
      );
      expect(acquired.getOrNull(), 'lease-options');
      await pool.release('lease-options');

      final diagnostics = pool.getHealthDiagnostics();
      expect(diagnostics['effective_strategy'], 'lease');
      expect(diagnostics['native_skip_reason'], 'connection_options_unsupported');
      expect(diagnostics['native_options_skip_total'], 1);
      expect(metrics.odbcNativePoolOptionsSkipCount, 1);
      verifyNever(() => service.poolCreate(any(), any(), options: any(named: 'options')));
      verify(() => service.connect('DSN=Prod', options: any(named: 'options'))).called(1);
    });

    test('uses native-compatible acquire and preserves lease options on native fallback', () async {
      when(() => configRepository.getCurrentConfig()).thenAnswer(
        (_) async => Success(_sqlServerConfig()),
      );
      when(
        () => service.poolCreate(
          any(),
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => const Failure(
          ConnectionError(message: 'invalid connection id'),
        ),
      );
      when(
        () => service.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'lease-native-compatible-fallback',
            connectionString: 'DSN=Prod',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );

      final pool = _buildPool(
        service: service,
        settings: settings,
        flags: flags,
        metrics: metrics,
        configRepository: configRepository,
      );

      const fallbackOptions = ConnectionOptions(
        queryTimeout: Duration(seconds: 7),
        maxResultBufferBytes: 16 * 1024 * 1024,
      );
      final acquired = await pool.acquireNativeCompatible(
        'DSN=Prod',
        leaseFallbackOptions: fallbackOptions,
      );

      expect(acquired.getOrNull(), 'lease-native-compatible-fallback');
      expect(metrics.odbcNativeCompatibleAcquireAttemptCount, 1);
      expect(metrics.odbcNativeCompatibleAcquireSuccessCount, 0);
      verify(
        () => service.poolCreate('DSN=Prod;PoolTestOnCheckout=true', any(), options: any(named: 'options')),
      ).called(1);
      final captured =
          verify(() => service.connect('DSN=Prod', options: captureAny(named: 'options'))).captured.single
              as ConnectionOptions;
      expect(captured.queryTimeout, fallbackOptions.queryTimeout);
      expect(captured.maxResultBufferBytes, fallbackOptions.maxResultBufferBytes);
    });

    test('opens native circuit from execution-stage structural failure feedback', () async {
      when(() => configRepository.getCurrentConfig()).thenAnswer(
        (_) async => Success(_sqlServerConfig()),
      );
      when(
        () => service.poolCreate(
          any(),
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => const Success(41));
      when(() => service.poolGetConnection(41)).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'native-structural',
            connectionString: 'DSN=Prod',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => service.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'lease-after-feedback',
            connectionString: 'DSN=Prod',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );

      final pool = _buildPool(
        service: service,
        settings: settings,
        flags: flags,
        metrics: metrics,
        configRepository: configRepository,
        nativeCircuitBreakThreshold: 1,
        nativeCircuitBreakDuration: const Duration(minutes: 5),
      );

      final nativeAcquire = await pool.acquire('DSN=Prod');
      expect(nativeAcquire.getOrNull(), 'native-structural');

      pool.recordExecutionFailure(
        connectionString: 'DSN=Prod',
        connectionId: 'native-structural',
        error: domain.QueryExecutionFailure.withContext(
          message: 'Buffer too small',
          context: {'reason': 'buffer_too_small'},
        ),
        stage: 'query',
      );

      final leaseAcquire = await pool.acquire('DSN=Prod');
      expect(leaseAcquire.getOrNull(), 'lease-after-feedback');

      final diagnostics = pool.getHealthDiagnostics();
      expect(diagnostics['native_circuit_open'], isTrue);
      expect(diagnostics['native_execution_fallback_total'], 1);
      expect(metrics.odbcNativePoolFallbackCount, 1);
      verify(() => service.poolGetConnection(41)).called(1);
      verify(() => service.connect('DSN=Prod', options: any(named: 'options'))).called(1);
    });

    test('opens execution feedback circuit only for the failed connection string', () async {
      when(() => configRepository.getCurrentConfig()).thenAnswer(
        (_) async => Success(_sqlServerConfig()),
      );
      var nativeCounter = 0;
      when(
        () => service.poolCreate(
          any(),
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => Success(++nativeCounter));
      when(() => service.poolGetConnection(any())).thenAnswer((invocation) async {
        final poolId = invocation.positionalArguments.single as int;
        return Success(
          Connection(
            id: 'native-$poolId',
            connectionString: 'DSN=$poolId',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(
        () => service.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'lease-after-dsn-a-circuit',
            connectionString: 'DSN=A',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );

      final pool = _buildPool(
        service: service,
        settings: settings,
        flags: flags,
        metrics: metrics,
        configRepository: configRepository,
        nativeCircuitBreakThreshold: 1,
        nativeCircuitBreakDuration: const Duration(minutes: 5),
      );

      final dsnA = await pool.acquire('DSN=A');
      final dsnB = await pool.acquire('DSN=B');
      expect(dsnA.getOrNull(), 'native-1');
      expect(dsnB.getOrNull(), 'native-2');

      pool.recordExecutionFailure(
        connectionString: 'DSN=A',
        connectionId: 'native-1',
        error: domain.QueryExecutionFailure.withContext(
          message: 'Buffer too small',
          context: {'reason': 'buffer_too_small'},
        ),
        stage: 'query',
      );

      final dsnBAfterFeedback = await pool.acquire('DSN=B');
      expect(dsnBAfterFeedback.getOrNull(), 'native-2');
      final dsnAAfterFeedback = await pool.acquire('DSN=A');
      expect(dsnAAfterFeedback.getOrNull(), 'lease-after-dsn-a-circuit');

      expect(metrics.odbcNativePoolFallbackCount, 1);
      verify(() => service.poolGetConnection(any())).called(3);
      verify(() => service.connect('DSN=A', options: any(named: 'options'))).called(1);
    });

    test('falls back to lease pool on structured native timeout and records fallback metric', () async {
      when(() => configRepository.getCurrentConfig()).thenAnswer(
        (_) async => Success(_sqlServerConfig()),
      );
      when(
        () => service.poolCreate(
          any(),
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => const Failure(
          ConnectionError(message: 'ODBC worker busy timeout'),
        ),
      );
      when(
        () => service.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'lease-1',
            connectionString: 'DSN=Prod',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(() => service.disconnect('lease-1')).thenAnswer(
        (_) async => const Success(unit),
      );

      final pool = _buildPool(
        service: service,
        settings: settings,
        flags: flags,
        metrics: metrics,
        configRepository: configRepository,
      );

      final acquired = await pool.acquire('DSN=Prod');
      expect(acquired.getOrNull(), 'lease-1');

      final released = await pool.release('lease-1');
      expect(released.isSuccess(), isTrue);

      final diagnostics = pool.getHealthDiagnostics();
      expect(diagnostics['effective_strategy'], 'lease');
      expect(diagnostics['driver_type'], 'sqlServer');
      expect(diagnostics['native_eligible'], isTrue);
      expect(diagnostics['native_circuit_open'], isFalse);
      expect(diagnostics['native_circuit_failures'], 1);
      expect(metrics.odbcNativePoolFallbackCount, 1);
      verify(() => service.connect('DSN=Prod', options: any(named: 'options'))).called(1);
      verify(() => service.disconnect('lease-1')).called(1);
      verify(() => configRepository.getCurrentConfig()).called(1);
    });

    test('opens native circuit after repeated fallback and skips native attempts temporarily', () async {
      when(() => configRepository.getCurrentConfig()).thenAnswer(
        (_) async => Success(_sqlServerConfig()),
      );
      when(
        () => service.poolCreate(
          any(),
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => const Failure(
          ConnectionError(message: 'ODBC worker busy timeout'),
        ),
      );
      var leaseCounter = 0;
      when(
        () => service.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        leaseCounter++;
        return Success(
          Connection(
            id: 'lease-$leaseCounter',
            connectionString: 'DSN=Prod',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(() => service.disconnect(any())).thenAnswer(
        (_) async => const Success(unit),
      );

      final pool = _buildPool(
        service: service,
        settings: settings,
        flags: flags,
        metrics: metrics,
        configRepository: configRepository,
        nativeCircuitBreakThreshold: 2,
        nativeCircuitBreakDuration: const Duration(minutes: 5),
      );

      for (var i = 0; i < 3; i++) {
        final acquired = await pool.acquire('DSN=Prod');
        expect(acquired.isSuccess(), isTrue);
        await pool.release(acquired.getOrThrow());
      }

      final diagnostics = pool.getHealthDiagnostics();
      expect(diagnostics['native_circuit_open'], isTrue);
      expect(diagnostics['native_circuit_failures'], 2);
      expect(metrics.odbcNativePoolFallbackCount, 2);
      verify(
        () => service.poolCreate('DSN=Prod;PoolTestOnCheckout=true', any(), options: any(named: 'options')),
      ).called(2);
      verify(() => service.connect('DSN=Prod', options: any(named: 'options'))).called(3);
      verify(() => configRepository.getCurrentConfig()).called(1);
    });

    test('warms up eligible SQL Server driver through lease pool by default', () async {
      when(() => configRepository.getCurrentConfig()).thenAnswer(
        (_) async => Success(_sqlServerConfig()),
      );
      when(
        () => service.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'lease-warm-1',
            connectionString: 'DSN=Prod',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(() => service.disconnect(any())).thenAnswer(
        (_) async => const Success(unit),
      );

      final pool = _buildPool(
        service: service,
        settings: settings,
        flags: flags,
        metrics: metrics,
        configRepository: configRepository,
      );

      final result = await pool.warmUp('DSN=Prod', warmUpCount: 2);

      expect(result.isSuccess(), isTrue);
      final diagnostics = pool.getHealthDiagnostics();
      expect(diagnostics['native_warmup_enabled'], isFalse);
      expect(diagnostics['native_skip_reason'], 'native_warmup_disabled');
      verifyNever(() => service.poolCreate(any(), any(), options: any(named: 'options')));
      verify(() => service.connect('DSN=Prod', options: any(named: 'options'))).called(2);
      verify(() => service.disconnect(any())).called(2);
    });

    test('can opt into native warm-up for benchmarks and isolated pool validation', () async {
      when(() => configRepository.getCurrentConfig()).thenAnswer(
        (_) async => Success(_sqlServerConfig()),
      );
      when(
        () => service.poolCreate(
          any(),
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => const Success(51));
      var nativeCounter = 0;
      when(() => service.poolGetConnection(51)).thenAnswer((_) async {
        nativeCounter++;
        return Success(
          Connection(
            id: 'native-warm-$nativeCounter',
            connectionString: 'DSN=Prod',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        );
      });
      when(() => service.poolReleaseConnection(any())).thenAnswer(
        (_) async => const Success(unit),
      );

      final pool = _buildPool(
        service: service,
        settings: settings,
        flags: flags,
        metrics: metrics,
        configRepository: configRepository,
        nativeWarmUpEnabled: true,
      );

      final result = await pool.warmUp('DSN=Prod', warmUpCount: 2);

      expect(result.isSuccess(), isTrue);
      final diagnostics = pool.getHealthDiagnostics();
      expect(diagnostics['native_warmup_enabled'], isTrue);
      expect(diagnostics['native_circuit_open'], isFalse);
      expect(diagnostics['native_circuit_failures'], 0);
      verify(
        () => service.poolCreate('DSN=Prod;PoolTestOnCheckout=true', any(), options: any(named: 'options')),
      ).called(1);
      verify(() => service.poolGetConnection(51)).called(2);
      verify(() => service.poolReleaseConnection(any())).called(2);
      verifyNever(() => service.connect(any(), options: any(named: 'options')));
    });

    test('keeps SQL Anywhere on lease pool and marks native as ineligible', () async {
      when(() => configRepository.getCurrentConfig()).thenAnswer(
        (_) async => Success(_sqlAnywhereConfig()),
      );
      when(
        () => service.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'lease-sqlany',
            connectionString: 'DSN=SQLAnywhere',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(() => service.disconnect('lease-sqlany')).thenAnswer(
        (_) async => const Success(unit),
      );

      final pool = _buildPool(
        service: service,
        settings: settings,
        flags: flags,
        metrics: metrics,
        configRepository: configRepository,
      );

      final acquired = await pool.acquire('DSN=SQLAnywhere');
      expect(acquired.getOrNull(), 'lease-sqlany');
      await pool.discard('lease-sqlany');

      final diagnostics = pool.getHealthDiagnostics();
      expect(diagnostics['effective_strategy'], 'lease');
      expect(diagnostics['driver_type'], 'sybaseAnywhere');
      expect(diagnostics['native_eligible'], isFalse);
      verifyNever(() => service.poolCreate(any(), any(), options: any(named: 'options')));
      verify(() => service.connect('DSN=SQLAnywhere', options: any(named: 'options'))).called(1);
      verify(() => configRepository.getCurrentConfig()).called(1);
    });

    test('invalidates cached driver info when configuration changes', () async {
      var config = _sqlServerConfig();
      when(() => configRepository.getCurrentConfig()).thenAnswer(
        (_) async => Success(config),
      );
      when(
        () => service.poolCreate(
          any(),
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => const Success(41));
      when(() => service.poolGetConnection(41)).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'native-before-config-change',
            connectionString: 'DSN=Prod',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(
        () => service.connect(
          any(),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Success(
          Connection(
            id: 'lease-after-config-change',
            connectionString: 'DSN=SQLAnywhere',
            createdAt: DateTime.now(),
            isActive: true,
          ),
        ),
      );
      when(() => service.disconnect('lease-after-config-change')).thenAnswer(
        (_) async => const Success(unit),
      );

      final pool = _buildPool(
        service: service,
        settings: settings,
        flags: flags,
        metrics: metrics,
        configRepository: configRepository,
        driverInfoCacheTtl: Duration.zero,
      );

      final nativeAcquire = await pool.acquire('DSN=Prod');
      expect(nativeAcquire.getOrNull(), 'native-before-config-change');

      config = _sqlAnywhereConfig().copyWith(
        updatedAt: DateTime(2024, 1, 2),
      );
      final leaseAcquire = await pool.acquire('DSN=SQLAnywhere');
      expect(leaseAcquire.getOrNull(), 'lease-after-config-change');

      final diagnostics = pool.getHealthDiagnostics();
      expect(diagnostics['driver_type'], 'sybaseAnywhere');
      expect(diagnostics['native_eligible'], isFalse);
      verify(
        () => service.poolCreate('DSN=Prod;PoolTestOnCheckout=true', any(), options: any(named: 'options')),
      ).called(1);
      verify(() => service.connect('DSN=SQLAnywhere', options: any(named: 'options'))).called(1);
    });
  });
}

AdaptiveOdbcConnectionPool _buildPool({
  required _MockOdbcService service,
  required MockOdbcConnectionSettings settings,
  required FeatureFlags flags,
  required MetricsCollector metrics,
  required IAgentConfigRepository configRepository,
  int nativeCircuitBreakThreshold = 3,
  Duration nativeCircuitBreakDuration = const Duration(minutes: 1),
  bool nativeWarmUpEnabled = false,
  Duration driverInfoCacheTtl = const Duration(seconds: 10),
}) {
  return AdaptiveOdbcConnectionPool(
    leasePool: OdbcConnectionPool(
      service,
      settings,
      metricsCollector: metrics,
    ),
    nativePool: OdbcNativeConnectionPool(
      service,
      settings,
      metricsCollector: metrics,
    ),
    featureFlags: flags,
    metricsCollector: metrics,
    configRepository: configRepository,
    nativeCircuitBreakThreshold: nativeCircuitBreakThreshold,
    nativeCircuitBreakDuration: nativeCircuitBreakDuration,
    nativeWarmUpEnabled: nativeWarmUpEnabled,
    driverInfoCacheTtl: driverInfoCacheTtl,
  );
}

Config _sqlServerConfig() {
  return Config(
    id: 'cfg-sqlserver',
    driverName: 'SQL Server',
    odbcDriverName: 'ODBC Driver 17 for SQL Server',
    connectionString: 'DRIVER={ODBC Driver 17 for SQL Server};SERVER=.;DATABASE=db;',
    username: 'sa',
    databaseName: 'db',
    host: 'localhost',
    port: 1433,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

Config _sqlAnywhereConfig() {
  return Config(
    id: 'cfg-sqlany',
    driverName: 'SQL Anywhere',
    odbcDriverName: 'SQL Anywhere',
    connectionString: 'DRIVER={SQL Anywhere};DBN=db;UID=dba;',
    username: 'dba',
    databaseName: 'db',
    host: 'localhost',
    port: 2638,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}
