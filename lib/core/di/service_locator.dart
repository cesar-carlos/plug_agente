import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/i_agent_config_repository.dart';
import '../../domain/repositories/i_database_gateway.dart';
import '../../domain/repositories/i_notification_service.dart';
import '../../domain/repositories/i_odbc_driver_checker.dart';
import '../../domain/repositories/i_transport_client.dart';
import '../../domain/repositories/i_auth_client.dart';
import '../../infrastructure/repositories/agent_config_repository.dart';
import '../../infrastructure/external_services/socket_io_transport_client.dart';
import '../../infrastructure/external_services/odbc_database_gateway.dart';
import '../../infrastructure/external_services/odbc_driver_checker.dart';
import '../../infrastructure/external_services/auth_client.dart';
import '../../infrastructure/external_services/dio_factory.dart';
import '../../infrastructure/datasources/socket_data_source.dart';
import '../../infrastructure/compression/gzip_compressor.dart';
import '../../infrastructure/repositories/agent_config_drift_database.dart';
import '../../infrastructure/services/notification_service.dart';
import '../../core/services/tray_manager_service.dart';
import '../../application/services/connection_service.dart';
import '../../application/services/query_normalizer_service.dart';
import '../../application/services/compression_service.dart';
import '../../application/services/config_service.dart';
import '../../application/services/update_service.dart';
import '../../application/services/query_processing_service.dart';
import '../../application/services/auth_service.dart';
import '../../application/validation/config_validator.dart';
import '../../application/validation/query_normalizer.dart';
import '../../application/use_cases/check_odbc_driver.dart';
import '../../application/use_cases/connect_to_hub.dart';
import '../../application/use_cases/execute_playground_query.dart';
import '../../application/use_cases/handle_query_request.dart';
import '../../application/use_cases/test_db_connection.dart';
import '../../application/use_cases/save_agent_config.dart';
import '../../application/use_cases/load_agent_config.dart';
import '../../application/use_cases/check_for_updates.dart';
import '../../application/use_cases/cancel_all_notifications.dart';
import '../../application/use_cases/cancel_notification.dart';
import '../../application/use_cases/send_notification.dart';
import '../../application/use_cases/schedule_notification.dart';
import '../../application/use_cases/login_user.dart';
import '../../application/use_cases/refresh_auth_token.dart';
import '../../application/use_cases/save_auth_token.dart';

final getIt = GetIt.instance;

Future<void> setupDependencies() async {
  // External
  getIt.registerLazySingleton(() => const Uuid());
  getIt.registerLazySingleton(() => SocketDataSource());
  getIt.registerLazySingleton(() => GzipCompressor());
  getIt.registerLazySingleton(() => ConfigValidator());
  getIt.registerLazySingleton(() => QueryNormalizer());

  // Tray Service
  getIt.registerLazySingleton(() => TrayManagerService());

  // Notification Service
  getIt.registerLazySingleton<INotificationService>(() => NotificationService());

  // Database
  getIt.registerLazySingleton(() => AppDatabase());

  // Repositories
  getIt.registerLazySingleton<IAgentConfigRepository>(() => AgentConfigRepository(getIt<AppDatabase>()));

  getIt.registerLazySingleton<ITransportClient>(() => SocketIOTransportClient(getIt<SocketDataSource>()));

  getIt.registerLazySingleton<IDatabaseGateway>(() => OdbcDatabaseGateway(getIt<IAgentConfigRepository>()));

  getIt.registerLazySingleton<IOdbcDriverChecker>(() => OdbcDriverChecker());

  // Auth Client
  getIt.registerLazySingleton<IAuthClient>(() => AuthClient(DioFactory.createDio()));

  // Services
  getIt.registerLazySingleton(() => ConnectionService(getIt<ITransportClient>(), getIt<IDatabaseGateway>()));

  getIt.registerLazySingleton(() => AuthService(getIt<IAuthClient>(), getIt<IAgentConfigRepository>()));

  getIt.registerLazySingleton(() => QueryNormalizerService(getIt<QueryNormalizer>()));

  getIt.registerLazySingleton(() => CompressionService(getIt<GzipCompressor>()));

  getIt.registerLazySingleton(() => ConfigService(getIt<ConfigValidator>()));

  getIt.registerLazySingleton(
    () => UpdateService(
      'https://api.example.com/updates', // This should be configurable
      DioFactory.createDio(),
    ),
  );

  getIt.registerLazySingleton(() => QueryProcessingService(getIt<ITransportClient>(), getIt<HandleQueryRequest>()));

  // Use cases
  getIt.registerLazySingleton(() => ConnectToHub(getIt<ConnectionService>()));

  getIt.registerLazySingleton(
    () => HandleQueryRequest(
      getIt<IDatabaseGateway>(),
      getIt<ITransportClient>(),
      getIt<QueryNormalizerService>(),
      getIt<CompressionService>(),
    ),
  );

  getIt.registerLazySingleton(() => TestDbConnection(getIt<ConnectionService>()));

  getIt.registerLazySingleton(() => CheckOdbcDriver(getIt<IOdbcDriverChecker>()));

  getIt.registerLazySingleton(
    () => ExecutePlaygroundQuery(getIt<IDatabaseGateway>(), getIt<IAgentConfigRepository>(), getIt<Uuid>()),
  );

  getIt.registerLazySingleton(() => SaveAgentConfig(getIt<IAgentConfigRepository>(), getIt<ConfigService>()));

  getIt.registerLazySingleton(() => LoadAgentConfig(getIt<IAgentConfigRepository>()));

  getIt.registerLazySingleton(() => CheckForUpdates(getIt<UpdateService>()));

  getIt.registerLazySingleton(() => SendNotification(getIt<INotificationService>()));

  getIt.registerLazySingleton(() => ScheduleNotification(getIt<INotificationService>()));

  getIt.registerLazySingleton(() => CancelNotification(getIt<INotificationService>()));

  getIt.registerLazySingleton(() => CancelAllNotifications(getIt<INotificationService>()));

  getIt.registerLazySingleton(() => LoginUser(getIt<AuthService>()));

  getIt.registerLazySingleton(() => RefreshAuthToken(getIt<AuthService>()));

  getIt.registerLazySingleton(() => SaveAuthToken(getIt<AuthService>()));

  // Initialize database
  final database = getIt<AppDatabase>();
  await database.customStatement('PRAGMA foreign_keys = ON');
}
