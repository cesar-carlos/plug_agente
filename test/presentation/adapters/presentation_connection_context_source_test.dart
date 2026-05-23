import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/presentation/adapters/presentation_connection_context_source.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}

class _MockConfigProvider extends Mock implements ConfigProvider {}

void main() {
  late HubConnectionTrackingState trackingState;
  late _MockAuthProvider authProvider;
  late _MockConfigProvider configProvider;
  late PresentationConnectionContextSource source;

  setUp(() {
    trackingState = HubConnectionTrackingState()
      ..lastConfigId = 'cfg-1'
      ..lastServerUrl = 'https://hub.test'
      ..lastAgentId = 'agent-1'
      ..lastAuthToken = 'tok-1';
    authProvider = _MockAuthProvider();
    configProvider = _MockConfigProvider();
    when(() => configProvider.currentConfig).thenReturn(null);
    source = PresentationConnectionContextSource(
      trackingState: trackingState,
      authProvider: () => authProvider,
      configProvider: () => configProvider,
    );
  });

  test('should resolve connection context from tracked state', () {
    final context = source.resolveConnectionContext();

    expect(context, isNotNull);
    expect(context!.configId, 'cfg-1');
    expect(context.serverUrl, 'https://hub.test');
    expect(context.agentId, 'agent-1');
  });

  test('should resolve active config id from candidate when provided', () {
    expect(source.resolveActiveConfigId(' cfg-2 '), 'cfg-2');
  });

  test('should return null auth token when session is marked invalid', () {
    trackingState.sessionAuthInvalid = true;
    when(() => authProvider.currentTokenForConfig(any())).thenReturn(null);

    expect(source.resolveAuthTokenForReconnect(), isNull);
  });

  test('should fall back to tracked config auth token when live token is absent', () {
    when(() => authProvider.currentTokenForConfig(any())).thenReturn(null);
    when(() => configProvider.currentConfig).thenReturn(
      Config(
        id: 'cfg-1',
        driverName: 'SQL Server',
        odbcDriverName: 'ODBC Driver 17 for SQL Server',
        connectionString: '',
        username: '',
        databaseName: '',
        host: 'localhost',
        port: 1433,
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
        serverUrl: 'https://hub.test',
        agentId: 'agent-1',
        authToken: 'config-token',
      ),
    );

    expect(source.resolveAuthTokenForReconnect(), 'config-token');
  });
}
