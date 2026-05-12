import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/app_environment.dart';

void main() {
  group('AppEnvironment', () {
    test('reads values loaded into dotenv', () {
      dotenv.loadFromString(
        envString: 'APP_ENVIRONMENT_TEST_VALUE=from-dotenv',
        isOptional: true,
      );

      expect(
        AppEnvironment.get('APP_ENVIRONMENT_TEST_VALUE'),
        'from-dotenv',
      );
    });

    test('loadOptional reads .env from current directory', () async {
      final previousCurrent = Directory.current;
      final tempDir = await Directory.systemTemp.createTemp('plug_env_test_');
      try {
        await File('${tempDir.path}${Platform.pathSeparator}.env').writeAsString(
          'APP_ENVIRONMENT_TEST_FILE_VALUE=from-file',
        );
        Directory.current = tempDir;

        await AppEnvironment.loadOptional();

        expect(
          AppEnvironment.get('APP_ENVIRONMENT_TEST_FILE_VALUE'),
          'from-file',
        );
      } finally {
        Directory.current = previousCurrent;
        await tempDir.delete(recursive: true);
      }
    });
  });
}
