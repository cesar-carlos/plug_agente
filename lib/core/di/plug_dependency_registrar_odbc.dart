part of 'plug_dependency_registrar.dart';

void _registerOdbc(
  GetIt getIt, {
  required odbc.ServiceLocator odbcWorkerLocator,
}) {
  getIt
    ..registerLazySingleton<odbc.OdbcService>(
      () => odbcWorkerLocator.asyncService,
    )
    ..registerLazySingleton<IConnectionPool>(
      () => createOdbcConnectionPool(
        getIt<odbc.OdbcService>(),
        getIt<IOdbcConnectionSettings>(),
        getIt<MetricsCollector>(),
        getIt<FeatureFlags>(),
        getIt<ActiveConfigResolver>(),
      ),
    )
    ..registerLazySingleton<IRetryManager>(RetryManager.new)
    ..registerLazySingleton<SqlInvestigationCollector>(SqlInvestigationCollector.new)
    ..registerLazySingleton<ISqlInvestigationCollector>(getIt.get<SqlInvestigationCollector>)
    ..registerLazySingleton(MetricsCollector.new)
    ..registerLazySingleton(
      () => DirectOdbcConnectionLimiter(
        maxConcurrent: ConnectionConstants.directOdbcConnectionConcurrency(
          getIt<IOdbcConnectionSettings>().poolSize,
        ),
        acquireTimeout: ConnectionConstants.defaultPoolAcquireTimeout,
        metricsCollector: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => OdbcEventBridge(
        adminService: getIt<odbc.OdbcService>(),
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => OdbcNativeMetricsService(
        getIt<odbc.OdbcService>(),
        queryConfigSource: getIt<ActiveConfigResolver>(),
        connectionPool: getIt<IConnectionPool>(),
        settings: getIt<IOdbcConnectionSettings>(),
        runtimeTuning: getIt<OdbcRuntimeTuning>(),
        metricsCollector: getIt<MetricsCollector>(),
        eventBridge: getIt<OdbcEventBridge>(),
      ),
    )
    ..registerLazySingleton<IMetricsCollector>(getIt.get<MetricsCollector>)
    ..registerLazySingleton<SqlExecutionQueue>(
      () {
        final persistedPoolSize = getIt<IOdbcConnectionSettings>().poolSize;
        final sqlQueueMaxWorkers = ConnectionConstants.sqlQueueMaxWorkersForPoolSize(
          persistedPoolSize,
        );
        if (sqlQueueMaxWorkers == persistedPoolSize) {
          getIt<MetricsCollector>().recordSqlQueueWorkersEqualPool(
            workers: sqlQueueMaxWorkers,
            poolSize: persistedPoolSize,
          );
        }
        final sqlQueue = SqlExecutionQueue(
          maxQueueSize: ConnectionConstants.sqlQueueMaxSize,
          maxConcurrentWorkers: sqlQueueMaxWorkers,
          maxConcurrentBatchWorkers: ConnectionConstants.sqlQueueMaxBatchWorkersForWorkers(
            sqlQueueMaxWorkers,
            persistedPoolSize: persistedPoolSize,
          ),
          maxConcurrentLongQueryWorkers: ConnectionConstants.sqlQueueMaxLongQueryWorkersForWorkers(
            sqlQueueMaxWorkers,
            persistedPoolSize: persistedPoolSize,
          ),
          maxConcurrentStreamingWorkers: ConnectionConstants.sqlQueueMaxStreamingWorkersForWorkers(
            sqlQueueMaxWorkers,
            persistedPoolSize: persistedPoolSize,
          ),
          maxConcurrentNonQueryWorkers: ConnectionConstants.sqlQueueMaxNonQueryWorkersForWorkers(
            sqlQueueMaxWorkers,
            persistedPoolSize: persistedPoolSize,
          ),
          metricsCollector: getIt<MetricsCollector>(),
          defaultEnqueueTimeout: ConnectionConstants.sqlQueueEnqueueTimeout,
        );

        developer.log(
          'SQL queue initialized: maxSize=${ConnectionConstants.sqlQueueMaxSize}, '
          'maxWorkers=$sqlQueueMaxWorkers, '
          'batchWorkers=${sqlQueue.maxConcurrentBatchWorkers}, '
          'longQueryWorkers=${sqlQueue.maxConcurrentLongQueryWorkers}, '
          'streamingWorkers=${sqlQueue.maxConcurrentStreamingWorkers}, '
          'nonQueryWorkers=${sqlQueue.maxConcurrentNonQueryWorkers}',
          name: 'plug_dependency_registrar',
          level: 800,
        );

        return sqlQueue;
      },
    )
    ..registerLazySingleton<IDatabaseGateway>(
      () {
        final baseGateway = OdbcDatabaseGateway(
          getIt<ActiveConfigResolver>(),
          getIt<odbc.OdbcService>(),
          getIt<IConnectionPool>(),
          getIt<IRetryManager>(),
          getIt<MetricsCollector>(),
          getIt<IOdbcConnectionSettings>(),
          featureFlags: getIt<FeatureFlags>(),
          directConnectionLimiter: getIt<DirectOdbcConnectionLimiter>(),
          sqlInvestigation: getIt<ISqlInvestigationCollector>(),
        );

        return QueuedDatabaseGateway(
          delegate: baseGateway,
          queue: getIt<SqlExecutionQueue>(),
        );
      },
    )
    ..registerLazySingleton<IStreamingDatabaseGateway>(
      () {
        final baseStreamingGateway = OdbcStreamingGateway(
          getIt<odbc.OdbcService>(),
          getIt<IOdbcConnectionSettings>(),
          batchedQuerySource: OdbcBatchedStreamingQuerySource(
            asyncNative: odbcWorkerLocator.asyncNativeConnection,
            syncNative: odbcWorkerLocator.nativeConnection,
            isAsync: odbcWorkerLocator.isAsyncMode,
          ),
          directConnectionLimiter: getIt<DirectOdbcConnectionLimiter>(),
          metricsCollector: getIt<MetricsCollector>(),
        );

        return QueuedStreamingDatabaseGateway(
          delegate: baseStreamingGateway,
          queue: getIt<SqlExecutionQueue>(),
        );
      },
    )
    ..registerLazySingleton<IOdbcDriverChecker>(OdbcDriverChecker.new);
}
