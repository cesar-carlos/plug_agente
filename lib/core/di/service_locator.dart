import 'package:get_it/get_it.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/application/services/auth_service.dart';
import 'package:plug_agente/application/services/compression_service.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/services/connection_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/services/query_processing_service.dart';
import 'package:plug_agente/application/services/update_service.dart';
import 'package:plug_agente/application/use_cases/cancel_all_notifications.dart';
import 'package:plug_agente/application/use_cases/cancel_notification.dart';
import 'package:plug_agente/application/use_cases/check_for_updates.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/handle_query_request.dart';
import 'package:plug_agente/application/use_cases/load_agent_config.dart';
import 'package:plug_agente/application/use_cases/login_user.dart';
import 'package:plug_agente/application/use_cases/refresh_auth_token.dart';
import 'package:plug_agente/application/use_cases/save_agent_config.dart';
import 'package:plug_agente/application/use_cases/save_auth_token.dart';
import 'package:plug_agente/application/use_cases/schedule_notification.dart';
import 'package:plug_agente/application/use_cases/send_notification.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/core/services/tray_manager_service.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_auth_client.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/domain/repositories/i_odbc_driver_checker.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/compression/gzip_compressor.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/auth_client.dart';
import 'package:plug_agente/infrastructure/external_services/dio_factory.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_database_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_driver_checker.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_client.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_repository.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:plug_agente/infrastructure/services/notification_service.dart';
import 'package:uuid/uuid.dart';

final GetIt getIt = GetIt.instance;

Future<void> setupDependencies() async {
  // External
  getIt
    ..registerLazySingleton(SocketDataSource.new)
    ..registerLazySingleton(GzipCompressor.new)
    ..registerLazySingleton(ConfigValidator.new)
    ..registerLazySingleton(QueryNormalizer.new)
    ..registerLazySingleton(TrayManagerService.new)
    ..registerLazySingleton<INotificationService>(NotificationService.new)
    ..registerLazySingleton(AppDatabase.new)
    ..registerLazySingleton<IAgentConfigRepository>(
      () => AgentConfigRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<ITransportClient>(
      () => SocketIOTransportClient(getIt<SocketDataSource>()),
    )
    ..registerLazySingleton(() => const Uuid())
    ..registerLazySingleton(ServiceLocator.new)
    ..registerLazySingleton(() => OdbcService(getIt<IOdbcRepository>()))
    ..registerLazySingleton<IConnectionPool>(
      () => OdbcConnectionPool(getIt<OdbcService>()),
    )
    ..registerLazySingleton<IRetryManager>(() => RetryManager.instance)
    ..registerLazySingleton(() => MetricsCollector.instance)
    ..registerLazySingleton<IDatabaseGateway>(
      () => OdbcDatabaseGateway(
        getIt<IAgentConfigRepository>(),
        getIt<OdbcService>(),
        getIt<IConnectionPool>(),
        getIt<IRetryManager>(),
        getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton<IOdbcDriverChecker>(OdbcDriverChecker.new)
    ..registerLazySingleton<IAuthClient>(
      () => AuthClient(DioFactory.createDio()),
    )
    ..registerLazySingleton(
      () => ConnectionService(
        getIt<ITransportClient>(),
        getIt<IDatabaseGateway>(),
      ),
    )
    ..registerLazySingleton(
      () => AuthService(getIt<IAuthClient>(), getIt<IAgentConfigRepository>()),
    )
    ..registerLazySingleton(
      () => QueryNormalizerService(getIt<QueryNormalizer>()),
    )
    ..registerLazySingleton(
      () => CompressionService(getIt<GzipCompressor>()),
    )
    ..registerLazySingleton(() => ConfigService(getIt<ConfigValidator>()))
    ..registerLazySingleton(
      () => UpdateService(
        'https://api.example.com/updates', // This should be configurable
        DioFactory.createDio(),
      ),
    )
    ..registerLazySingleton(
      () => QueryProcessingService(
        getIt<ITransportClient>(),
        getIt<HandleQueryRequest>(),
      ),
    )
    ..registerLazySingleton(() => ConnectToHub(getIt<ConnectionService>()))
    ..registerLazySingleton(
      () => HandleQueryRequest(
        getIt<IDatabaseGateway>(),
        getIt<ITransportClient>(),
        getIt<QueryNormalizerService>(),
        getIt<CompressionService>(),
      ),
    )
    ..registerLazySingleton(
      () => TestDbConnection(getIt<ConnectionService>()),
    )
    ..registerLazySingleton(
      () => CheckOdbcDriver(getIt<IOdbcDriverChecker>()),
    )
    ..registerLazySingleton(
      () => ExecutePlaygroundQuery(
        getIt<IDatabaseGateway>(),
        getIt<IAgentConfigRepository>(),
        getIt<Uuid>(),
      ),
    )
    ..registerLazySingleton(
      () => SaveAgentConfig(
        getIt<IAgentConfigRepository>(),
        getIt<ConfigService>(),
      ),
    )
    ..registerLazySingleton(
      () => LoadAgentConfig(getIt<IAgentConfigRepository>()),
    )
    ..registerLazySingleton(() => CheckForUpdates(getIt<UpdateService>()))
    ..registerLazySingleton(
      () => SendNotification(getIt<INotificationService>()),
    )
    ..registerLazySingleton(
      () => ScheduleNotification(getIt<INotificationService>()),
    )
    ..registerLazySingleton(
      () => CancelNotification(getIt<INotificationService>()),
    )
    ..registerLazySingleton(
      () => CancelAllNotifications(getIt<INotificationService>()),
    )
    ..registerLazySingleton(() => LoginUser(getIt<AuthService>()))
    ..registerLazySingleton(() => RefreshAuthToken(getIt<AuthService>()))
    ..registerLazySingleton(() => SaveAuthToken(getIt<AuthService>()));

  // Initialize database
  final database = getIt<AppDatabase>();
  await database.customStatement('PRAGMA foreign_keys = ON');
}
