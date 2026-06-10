import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_config_locator.dart';

void main() {
  group('DeveloperData7ConfigLocator', () {
    late Directory tempDir;
    late File configFile;
    late DeveloperData7ConfigLocator locator;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('data7_locator_test_');
      configFile = File('${tempDir.path}${Platform.pathSeparator}Data7.Config');
      await configFile.writeAsString('<Configurações><Item ID="a"><Descricao>x</Descricao></Item></Configurações>');
      locator = DeveloperData7ConfigLocator(pathValidator: ActionPathValidator());
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('rejects config outside working directory allowlist when enforcement enabled', () async {
      final result = await locator.locate(
        actionId: 'action-1',
        configuredPath: AgentActionPathReference(originalPath: configFile.path),
        pathPolicy: const AgentActionPathPolicy(allowedWorkingDirectories: {r'C:\Other'}),
        phase: 'definition_validation',
      );

      expect(result.isError(), isTrue);
    });

    test('allows config discovery outside working directory allowlist for editor listing', () async {
      final result = await locator.locate(
        actionId: 'action-1',
        configuredPath: AgentActionPathReference(originalPath: configFile.path),
        pathPolicy: const AgentActionPathPolicy(allowedWorkingDirectories: {r'C:\Other'}),
        phase: 'definition_validation',
        enforceWorkingDirectoryAllowlist: false,
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().path.canonicalPath, isNotEmpty);
    });

    test('allows config discovery in production profile without working directory allowlist', () async {
      dotenv.loadFromString(envString: 'AGENT_OPERATIONAL_PROFILE=prod');

      final result = await locator.locate(
        actionId: 'action-1',
        configuredPath: AgentActionPathReference(originalPath: configFile.path),
        pathPolicy: const AgentActionPathPolicy(),
        phase: 'definition_validation',
        enforceWorkingDirectoryAllowlist: false,
      );

      expect(result.isSuccess(), isTrue, reason: result.exceptionOrNull()?.toString());
    });
  });
}
