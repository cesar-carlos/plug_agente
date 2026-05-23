import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';

void main() {
  group('ActionPathValidator', () {
    test('should validate existing working directory and return canonical path', () async {
      final validator = ActionPathValidator(
        directoryExists: (_) async => true,
        canonicalizeDirectory: (_) async => r'C:\Canonical\Data7',
      );

      final result = await validator.validateWorkingDirectory(
        actionId: 'action-1',
        path: const AgentActionPathReference(originalPath: r'C:\Data7'),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().path?.canonicalPath, r'C:\Canonical\Data7');
    });

    test('should reject missing working directory', () async {
      final validator = ActionPathValidator(
        directoryExists: (_) async => false,
      );

      final result = await validator.validateWorkingDirectory(
        actionId: 'action-1',
        path: const AgentActionPathReference(originalPath: r'C:\Missing'),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionPathContextConstants.directoryNotFoundReason),
      );
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('phase', 'definition_validation'),
      );
    });

    test('should include user_message when required file is missing', () async {
      final validator = ActionPathValidator(
        fileExists: (_) async => false,
      );

      final result = await validator.validateRequiredFile(
        actionId: 'action-1',
        field: 'executablePath',
        path: const AgentActionPathReference(originalPath: r'C:\Missing\app.exe'),
        allowedExtensions: {'.exe'},
        phase: 'execution_preflight',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context, containsPair('reason', AgentActionPathContextConstants.fileNotFoundReason));
      expect(failure.context, containsPair('phase', 'execution_preflight'));
      expect(failure.context['user_message'], isA<String>());
      expect((failure.context['user_message']! as String).trim(), isNotEmpty);
    });

    test('should reject working directory outside allowlist after canonicalization', () async {
      final validator = ActionPathValidator(
        directoryExists: (_) async => true,
        canonicalizeDirectory: (path) async {
          return switch (path) {
            r'C:\Data7\Jobs' => r'C:\Data7\Jobs',
            r'C:\Allowed' => r'C:\Allowed',
            _ => path,
          };
        },
      );

      final result = await validator.validateWorkingDirectory(
        actionId: 'action-1',
        path: const AgentActionPathReference(originalPath: r'C:\Data7\Jobs'),
        pathPolicy: const AgentActionPathPolicy(
          allowedWorkingDirectories: {r'C:\Allowed'},
        ),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionPathContextConstants.workingDirectoryNotAllowedReason),
      );
    });

    test('should accept working directory inside allowlist after canonicalization', () async {
      final validator = ActionPathValidator(
        directoryExists: (_) async => true,
        canonicalizeDirectory: (path) async {
          return switch (path) {
            r'C:\Data7\Jobs' => r'C:\Allowed\Jobs',
            r'C:\Allowed' => r'C:\Allowed',
            _ => path,
          };
        },
      );

      final result = await validator.validateWorkingDirectory(
        actionId: 'action-1',
        path: const AgentActionPathReference(originalPath: r'C:\Data7\Jobs'),
        pathPolicy: const AgentActionPathPolicy(
          allowedWorkingDirectories: {r'C:\Allowed'},
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().path?.canonicalPath, r'C:\Allowed\Jobs');
    });

    test('should validate json context file with size limit', () async {
      final validator = ActionPathValidator(
        fileExists: (_) async => true,
        canonicalizeFile: (_) async => r'C:\Temp\context.json',
        fileLength: (_) async => 16,
        readText: (_) async => '{"ok": true}',
      );

      final result = await validator.validateContextFile(
        actionId: 'action-1',
        contextPath: r'C:\Temp\context.json',
        policy: const AgentActionContextPolicy(
          maxContextBytes: 32,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().path?.sizeBytes, 16);
      expect(result.getOrThrow().path?.contentHash, startsWith('sha256:'));
    });

    test('should validate json context file against configured schema', () async {
      final validator = ActionPathValidator(
        fileExists: (_) async => true,
        canonicalizeFile: (_) async => r'C:\Temp\context.json',
        fileLength: (_) async => 16,
        readText: (_) async => '{"name": "backup"}',
      );

      final result = await validator.validateContextFile(
        actionId: 'action-1',
        contextPath: r'C:\Temp\context.json',
        policy: const AgentActionContextPolicy(
          contextJsonSchema: {
            'type': 'object',
            'required': ['name'],
            'properties': {
              'name': {'type': 'string'},
            },
          },
        ),
      );

      expect(result.isSuccess(), isTrue);
    });

    test('should reject json context file outside configured schema', () async {
      final validator = ActionPathValidator(
        fileExists: (_) async => true,
        canonicalizeFile: (_) async => r'C:\Temp\context.json',
        fileLength: (_) async => 16,
        readText: (_) async => '{"name": 123}',
      );

      final result = await validator.validateContextFile(
        actionId: 'action-1',
        contextPath: r'C:\Temp\context.json',
        policy: const AgentActionContextPolicy(
          contextJsonSchema: {
            'type': 'object',
            'required': ['name'],
            'properties': {
              'name': {'type': 'string'},
            },
          },
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      final actionFailure = failure! as ActionValidationFailure;
      expect(
        actionFailure.context,
        containsPair('reason', AgentActionPathContextConstants.invalidContextJsonSchemaReason),
      );
      expect(actionFailure.context, containsPair('field', 'contextPath'));
    });

    test('should reject invalid configured json schema during context validation', () async {
      final validator = ActionPathValidator(
        fileExists: (_) async => true,
        canonicalizeFile: (_) async => r'C:\Temp\context.json',
        fileLength: (_) async => 16,
        readText: (_) async => '{"name": "backup"}',
      );

      final result = await validator.validateContextFile(
        actionId: 'action-1',
        contextPath: r'C:\Temp\context.json',
        policy: const AgentActionContextPolicy(
          contextJsonSchema: {
            'type': 'not-a-json-schema-type',
          },
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect(
        (failure! as ActionValidationFailure).context,
        containsPair('reason', AgentActionValidationConstants.invalidContextJsonSchemaDefinitionReason),
      );
    });

    test('should reject context file outside allowlist before reading content', () async {
      var readCount = 0;
      final validator = ActionPathValidator(
        fileExists: (_) async => true,
        canonicalizeFile: (_) async => r'C:\Temp\context.json',
        canonicalizeDirectory: (_) async => r'C:\Allowed',
        fileLength: (_) async => 16,
        readText: (_) async {
          readCount += 1;
          return '{"ok": true}';
        },
      );

      final result = await validator.validateContextFile(
        actionId: 'action-1',
        contextPath: r'C:\Temp\context.json',
        policy: const AgentActionContextPolicy(),
        pathPolicy: const AgentActionPathPolicy(
          allowedContextDirectories: {r'C:\Allowed'},
        ),
      );

      expect(result.isError(), isTrue);
      expect(readCount, 0);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionPathContextConstants.contextFileNotAllowedReason),
      );
    });

    test('should reject invalid context json', () async {
      final validator = ActionPathValidator(
        fileExists: (_) async => true,
        fileLength: (_) async => 16,
        readText: (_) async => '{invalid',
      );

      final result = await validator.validateContextFile(
        actionId: 'action-1',
        contextPath: r'C:\Temp\context.json',
        policy: const AgentActionContextPolicy(),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionPathContextConstants.invalidContextJsonReason),
      );
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('phase', 'execution_preflight'),
      );
    });

    test('should capture last modified metadata for required files', () async {
      final tempDir = await Directory.systemTemp.createTemp('plug_path_meta_');
      final file = File('${tempDir.path}${Platform.pathSeparator}tool.exe');
      await file.writeAsBytes(<int>[1, 2, 3, 4]);

      try {
        final validator = ActionPathValidator();
        final result = await validator.validateRequiredFile(
          actionId: 'action-1',
          field: 'executablePath',
          path: AgentActionPathReference(originalPath: file.path),
          allowedExtensions: const {'.exe'},
        );

        expect(result.isSuccess(), isTrue);
        expect(result.getOrThrow().path?.lastModifiedUtc, isNotNull);
        expect(result.getOrThrow().path?.sizeBytes, 4);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('should reject context file larger than policy limit', () async {
      final validator = ActionPathValidator(
        fileExists: (_) async => true,
        fileLength: (_) async => 128,
      );

      final result = await validator.validateContextFile(
        actionId: 'action-1',
        contextPath: r'C:\Temp\context.txt',
        policy: const AgentActionContextPolicy(
          maxContextBytes: 32,
        ),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionPathContextConstants.contextFileTooLargeReason),
      );
    });

    test('should reject path snapshot drift after save when policy is failIfChanged', () {
      final validator = ActionPathValidator();

      final result = validator.ensurePathSnapshotMatchesCurrent(
        actionId: 'action-1',
        field: 'workingDirectory',
        savedReference: const AgentActionPathReference(
          originalPath: r'C:\Jobs',
          canonicalPath: r'C:\Saved\Jobs',
          pathChangePolicy: AgentActionPathChangePolicy.failIfChanged,
        ),
        currentPath: const AgentActionValidatedPath(
          originalPath: r'C:\Jobs',
          canonicalPath: r'C:\Current\Jobs',
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, AgentActionFailureCode.pathSnapshotMismatch);
      expect(failure.context, containsPair('reason', AgentActionPathContextConstants.pathChangedAfterSaveReason));
      expect(failure.context, containsPair('phase', 'execution_preflight'));
      expect(failure.context['user_message'], isA<String>());
      expect((failure.context['user_message']! as String).trim(), isNotEmpty);
    });

    test('should warn on path snapshot drift when policy is warnIfChanged', () {
      final validator = ActionPathValidator();
      final diagnostics = <String, Object?>{};

      final guardResult = validator.guardPathSnapshot(
        actionId: 'action-1',
        field: 'workingDirectory',
        savedReference: const AgentActionPathReference(
          originalPath: r'C:\Jobs',
          canonicalPath: r'C:\Saved\Jobs',
          pathChangePolicy: AgentActionPathChangePolicy.warnIfChanged,
        ),
        currentPath: const AgentActionValidatedPath(
          originalPath: r'C:\Jobs',
          canonicalPath: r'C:\Current\Jobs',
        ),
        diagnostics: diagnostics,
      );

      expect(guardResult.isSuccess(), isTrue);
      final warnings = diagnostics['path_snapshot_warnings'];
      expect(warnings, isA<List<Object?>>());
      expect((warnings! as List<dynamic>).length, 1);
    });

    test('should allow path snapshot drift when policy is allowChanged', () {
      final validator = ActionPathValidator();

      final result = validator.ensurePathSnapshotMatchesCurrent(
        actionId: 'action-1',
        field: 'workingDirectory',
        savedReference: const AgentActionPathReference(
          originalPath: r'C:\Jobs',
          canonicalPath: r'C:\Saved\Jobs',
          pathChangePolicy: AgentActionPathChangePolicy.allowChanged,
        ),
        currentPath: const AgentActionValidatedPath(
          originalPath: r'C:\Jobs',
          canonicalPath: r'C:\Current\Jobs',
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().hasWarning, isFalse);
    });

    test('should reject content hash drift when policy is failIfChanged', () {
      final validator = ActionPathValidator();

      final result = validator.ensureValidationHashMatchesCurrent(
        actionId: 'action-1',
        field: 'contextPath',
        savedReference: const AgentActionPathReference(
          originalPath: r'C:\ctx.json',
          canonicalPath: r'C:\ctx.json',
          validationHash: 'sha256:old',
          pathChangePolicy: AgentActionPathChangePolicy.failIfChanged,
        ),
        currentPath: const AgentActionValidatedPath(
          originalPath: r'C:\ctx.json',
          canonicalPath: r'C:\ctx.json',
          contentHash: 'sha256:new',
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(
        failure.context,
        containsPair('reason', AgentActionPathContextConstants.pathContentChangedAfterSaveReason),
      );
    });

    test('should require working directory allowlist in production profile', () async {
      final validator = ActionPathValidator(
        isProductionProfile: () => true,
      );

      final result = await validator.validateWorkingDirectory(
        actionId: 'action-1',
        path: const AgentActionPathReference(originalPath: r'C:\Data7'),
        pathPolicy: const AgentActionPathPolicy(),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionPathContextConstants.productionPathAllowlistRequiredReason),
      );
    });

    test('should allow empty allowlist in non-production profile', () async {
      final validator = ActionPathValidator(
        directoryExists: (_) async => true,
        canonicalizeDirectory: (_) async => r'C:\Data7',
        isProductionProfile: () => false,
      );

      final result = await validator.validateWorkingDirectory(
        actionId: 'action-1',
        path: const AgentActionPathReference(originalPath: r'C:\Data7'),
        pathPolicy: const AgentActionPathPolicy(),
      );

      expect(result.isSuccess(), isTrue);
    });

    test('should reject required file in production when allowlist is empty', () async {
      final validator = ActionPathValidator(
        fileExists: (_) async => true,
        canonicalizeFile: (_) async => r'C:\Apps\tool.exe',
        isProductionProfile: () => true,
      );

      final result = await validator.validateRequiredFile(
        actionId: 'action-1',
        field: 'executablePath',
        path: const AgentActionPathReference(originalPath: r'C:\Apps\tool.exe'),
        allowedExtensions: {'.exe'},
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionPathContextConstants.productionPathAllowlistRequiredReason),
      );
    });
  });
}
