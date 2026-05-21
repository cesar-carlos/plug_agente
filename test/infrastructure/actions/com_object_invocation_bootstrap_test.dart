import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_bootstrap.dart';
import 'package:plug_agente/infrastructure/actions/com_object_production_registrations.dart';
import 'package:plug_agente/infrastructure/actions/com_object_stub_invocation_handler.dart';

void main() {
  group('ComObjectInvocationBootstrap', () {
    test('should return empty registrations when stub env is disabled', () {
      dotenv.loadFromString(
        envString: 'AGENT_ACTION_COM_STUB_ENABLED=false',
        isOptional: true,
      );

      final registrations = ComObjectInvocationBootstrap.buildStubRegistrationsFromEnvironment();

      expect(registrations, isEmpty);
    });

    test('should register stub handler when env is enabled', () {
      dotenv.loadFromString(
        envString: '''
AGENT_ACTION_COM_STUB_ENABLED=true
AGENT_ACTION_COM_STUB_PROG_ID=AgentAction.Test
AGENT_ACTION_COM_STUB_MEMBER_NAME=Ping
''',
        isOptional: true,
      );

      final registrations = ComObjectInvocationBootstrap.buildStubRegistrationsFromEnvironment();

      expect(registrations, hasLength(1));
      expect(registrations.first.progId, 'AgentAction.Test');
      expect(registrations.first.memberName, 'Ping');
    });

    test('should merge production registrations before stub env handlers', () {
      dotenv.loadFromString(
        envString: '''
AGENT_ACTION_COM_STUB_ENABLED=true
AGENT_ACTION_COM_STUB_PROG_ID=AgentAction.Test
AGENT_ACTION_COM_STUB_MEMBER_NAME=Ping
''',
        isOptional: true,
      );

      final registrations = ComObjectInvocationBootstrap.buildRegistrations();

      expect(buildComObjectProductionRegistrations(), isEmpty);
      expect(registrations, hasLength(1));
      expect(registrations.first.handler, isA<ComObjectStubInvocationHandler>());
    });

    test('should build registry from production and stub registrations', () {
      dotenv.loadFromString(
        envString: '''
AGENT_ACTION_COM_STUB_ENABLED=true
AGENT_ACTION_COM_STUB_PROG_ID=AgentAction.Test
AGENT_ACTION_COM_STUB_MEMBER_NAME=Ping
''',
        isOptional: true,
      );

      final registry = ComObjectInvocationBootstrap.createRegistry();

      expect(registry.isRegistered(progId: 'AgentAction.Test', memberName: 'Ping'), isTrue);
    });
  });
}
