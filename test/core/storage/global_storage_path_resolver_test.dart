import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';

void main() {
  group('GlobalStoragePathResolver', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'global_storage_resolver_test',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should return first writable candidate directory', () async {
      final writableCandidate = p.join(tempDir.path, 'candidate1');

      final resolvedDirectory =
          await GlobalStoragePathResolver.resolveWritableAppDirectory(
            candidateDirectories: <String>[writableCandidate],
          );

      expect(resolvedDirectory, writableCandidate);
      expect(await Directory(writableCandidate).exists(), isTrue);
    });

    test(
      'should skip invalid candidate and use next writable directory',
      () async {
        final invalidFile = File(p.join(tempDir.path, 'not_a_directory'));
        await invalidFile.writeAsString('locked');

        final writableCandidate = p.join(tempDir.path, 'candidate2');
        final resolvedDirectory =
            await GlobalStoragePathResolver.resolveWritableAppDirectory(
              candidateDirectories: <String>[
                invalidFile.path,
                writableCandidate,
              ],
            );

        expect(resolvedDirectory, writableCandidate);
        expect(await Directory(writableCandidate).exists(), isTrue);
      },
    );

    test('should throw GlobalStorageAccessException when all fail', () async {
      final invalidFileOne = File(p.join(tempDir.path, 'invalid_1'));
      final invalidFileTwo = File(p.join(tempDir.path, 'invalid_2'));
      await invalidFileOne.writeAsString('x');
      await invalidFileTwo.writeAsString('y');

      try {
        await GlobalStoragePathResolver.resolveWritableAppDirectory(
          candidateDirectories: <String>[
            invalidFileOne.path,
            invalidFileTwo.path,
          ],
        );
        fail('Expected GlobalStorageAccessException');
      } on GlobalStorageAccessException catch (error) {
        expect(error.attempts, isNotEmpty);
      }
    });

    test(
      'should resolve shared context with settings and database in same directory',
      () async {
        final writableCandidate = p.join(tempDir.path, 'shared_context');

        final context = await GlobalStoragePathResolver.resolveContext(
          candidateDirectories: <String>[writableCandidate],
        );

        expect(context.appDirectoryPath, writableCandidate);
        expect(
          context.settingsFilePath,
          p.join(writableCandidate, 'settings.json'),
        );
        expect(
          context.databaseFilePath,
          p.join(writableCandidate, 'agent_config.db'),
        );
      },
    );
  });
}
