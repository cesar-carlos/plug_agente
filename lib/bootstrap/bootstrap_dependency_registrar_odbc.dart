part of 'bootstrap_dependency_registrar.dart';

void _registerOdbc(
  GetIt getIt, {
  required odbc.ServiceLocator odbcWorkerLocator,
}) {
  if (!getIt.isRegistered<OdbcProfileRecommendedOptions>()) {
    getIt.registerSingleton<OdbcProfileRecommendedOptions>(
      OdbcProfileRecommendedOptions(
        connection: odbcWorkerLocator.recommendedConnectionOptions,
        pool: odbcWorkerLocator.recommendedPoolOptions,
      ),
    );
  }
  getIt.registerLazySingleton<IStreamingNamedParameterPreparer>(
    () => OdbcStreamingNamedParameterPreparer.instance,
  );
  getIt
    ..registerLazySingleton(OdbcConnectionStringTtlCache.new)
    ..registerLazySingleton<OdbcStreamingSessionCache>(
      () => OdbcStreamingSessionCache(
        odbcService: getIt<odbc.OdbcService>(),
      ),
    )
    ..registerLazySingleton<IOdbcStreamingSessionCache>(() => getIt<OdbcStreamingSessionCache>())
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
        recommendedOptions: getIt<OdbcProfileRecommendedOptions>(),
      ),
    )
    ..registerLazySingleton<IRetryManager>(RetryManager.new)
    ..registerLazySingleton<SqlInvestigationCollector>(SqlInvestigationCollector.new)
    ..registerLazySingleton<ISqlInvestigationCollector>(getIt.get<SqlInvestigationCollector>)
    ..registerLazySingleton(MetricsCollector.new)
    ..registerLazySingleton<SqlExecutionQueueMetricsCollector>(getIt.get<MetricsCollector>)
    ..registerLazySingleton<IAutoUpdateMetricsCollector>(getIt.get<MetricsCollector>)
    ..registerLazySingleton(
      () => DirectOdbcConnectionLimiter(
        maxConcurrent: ConnectionConstants.directOdbcConnectionConcurrency(
          getIt<IOdbcConnectionSettings>().poolSize,
        ),
        acquireTimeout: ConnectionConstants.defaultPoolAcquireTimeout,
        metricsCollector: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton<IMetricsCollector>(getIt.get<MetricsCollector>)
    ..registerLazySingleton<OdbcInFlightExecutionRegistry>(OdbcInFlightExecutionRegistry.new)
    ..registerLazySingleton<OdbcRuntimeLifecycle>(
      () => OdbcRuntimeLifecycle(getIt<odbc.OdbcService>()),
    )
    ..registerLazySingleton<OdbcDatabaseGateway>(
      () => OdbcDatabaseGateway(
        getIt<ActiveConfigResolver>(),
        getIt<ConfigService>(),
        getIt<odbc.OdbcService>(),
        getIt<IConnectionPool>(),
        getIt<IRetryManager>(),
        getIt<MetricsCollector>(),
        getIt<IOdbcConnectionSettings>(),
        featureFlags: getIt<FeatureFlags>(),
        directConnectionLimiter: getIt<DirectOdbcConnectionLimiter>(),
        sqlInvestigation: getIt<ISqlInvestigationCollector>(),
        inFlightExecutionRegistry: getIt<OdbcInFlightExecutionRegistry>(),
        runtimeLifecycle: getIt<OdbcRuntimeLifecycle>(),
        configQueryCache: getIt<IActiveConfigQueryCache>(),
        connectionStringCache: getIt<OdbcConnectionStringTtlCache>(),
      ),
    )
    ..registerLazySingleton<ISqlInFlightExecutionAbortPort>(
      () => getIt<OdbcDatabaseGateway>().inFlightAbortPort,
    )
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
          inFlightAbortPort: getIt<ISqlInFlightExecutionAbortPort>(),
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
    ..registerLazySingleton<ISqlExecutionIdleWaitPort>(
      () => SqlExecutionIdleWaitAdapter(getIt<SqlExecutionQueue>()),
    )
    ..registerLazySingleton<OdbcStreamingGateway>(
      () => OdbcStreamingGateway(
        getIt<odbc.OdbcService>(),
        getIt<IOdbcConnectionSettings>(),
        recommendedOptions: getIt<OdbcProfileRecommendedOptions>(),
        batchedQuerySource: OdbcBatchedStreamingQuerySource(
          asyncNative: odbcWorkerLocator.asyncNativeConnection,
          syncNative: odbcWorkerLocator.nativeConnection,
          isAsync: odbcWorkerLocator.isAsyncMode,
        ),
        directConnectionLimiter: getIt<DirectOdbcConnectionLimiter>(),
        metricsCollector: getIt<MetricsCollector>(),
        inFlightExecutionRegistry: getIt<OdbcInFlightExecutionRegistry>(),
        runtimeLifecycle: getIt<OdbcRuntimeLifecycle>(),
        streamingSessionCache: getIt<OdbcStreamingSessionCache>(),
      ),
    )
    ..registerLazySingleton<IOdbcWorkerRuntimeRecoveryPort>(
      () => OdbcWorkerRuntimeRecoveryService(
        connectionPool: getIt<IConnectionPool>(),
        databaseGateway: getIt<OdbcDatabaseGateway>(),
        streamingGateway: getIt<OdbcStreamingGateway>(),
        runtimeLifecycle: getIt<OdbcRuntimeLifecycle>(),
        inFlightExecutionRegistry: getIt<OdbcInFlightExecutionRegistry>(),
        sqlExecutionIdleWaitPort: getIt<ISqlExecutionIdleWaitPort>(),
        streamingGatewayConcrete: getIt<OdbcStreamingGateway>(),
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => OdbcEventBridge(
        adminService: getIt<odbc.OdbcService>(),
        metrics: getIt<MetricsCollector>(),
        workerRecoveryPort: getIt<IOdbcWorkerRuntimeRecoveryPort>(),
      ),
    )
    ..registerLazySingleton(
      () => OdbcNativeMetricsService(
        getIt<odbc.OdbcService>(),
        queryConfigSource: getIt<ActiveConfigResolver>(),
        connectionStringSource: getIt<ConfigService>(),
        connectionPool: getIt<IConnectionPool>(),
        settings: getIt<IOdbcConnectionSettings>(),
        runtimeTuning: getIt<OdbcRuntimeTuning>(),
        metricsCollector: getIt<MetricsCollector>(),
        eventBridge: getIt<OdbcEventBridge>(),
      ),
    )
    ..registerLazySingleton<IDatabaseGateway>(
      () => QueuedDatabaseGateway(
        delegate: getIt<OdbcDatabaseGateway>(),
        queue: getIt<SqlExecutionQueue>(),
      ),
    )
    ..registerLazySingleton<IStreamingDatabaseGateway>(
      () => QueuedStreamingDatabaseGateway(
        delegate: getIt<OdbcStreamingGateway>(),
        queue: getIt<SqlExecutionQueue>(),
      ),
    )
    ..registerLazySingleton<IOdbcCircuitBreakerReset>(
      () => OdbcCircuitBreakerResetService(
        getIt<ConfigService>(),
        getIt<OdbcDatabaseGateway>(),
        getIt<OdbcStreamingGateway>(),
      ),
    )
    ..registerLazySingleton<IOdbcDriverChecker>(OdbcDriverChecker.new)
    ..registerLazySingleton<IOdbcApplicationRuntimeResetPort>(
      () => OdbcApplicationRuntimeResetService(getIt: getIt),
    )
    ..registerLazySingleton<IOdbcRuntimeReloadTeardownPort>(
      () => OdbcRuntimeReloadTeardownService(getIt: getIt),
    )
    ..registerLazySingleton<IOdbcRuntimeReloader>(
      () => OdbcRuntimeReloader(
        getIt: getIt,
        odbcWorkerLocator: odbcWorkerLocator,
        applicationRuntimeResetPort: getIt<IOdbcApplicationRuntimeResetPort>(),
        teardownPort: getIt<IOdbcRuntimeReloadTeardownPort>(),
      ),
    );
}
