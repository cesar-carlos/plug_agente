import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_failure_process_metadata.dart';

void main() {
  group('AgentActionFailureProcessMetadata', () {
    test('should extract process fields from failure context', () {
      final metadata = AgentActionFailureProcessMetadata.fromFailureContext(
        const <String, Object?>{
          'executable': r'C:\Tools\job.exe',
          'argument_count': 2,
          'command_preview': 'job.exe [REDACTED_ARGUMENTS]',
        },
      );

      expect(metadata.processExecutable, r'C:\Tools\job.exe');
      expect(metadata.processArgumentCount, 2);
      expect(metadata.processCommandPreview, 'job.exe [REDACTED_ARGUMENTS]');
      expect(metadata.isEmpty, isFalse);
    });

    test('should ignore blank executable and preview values', () {
      final metadata = AgentActionFailureProcessMetadata.fromFailureContext(
        const <String, Object?>{
          'executable': '   ',
          'command_preview': '',
        },
      );

      expect(metadata.processExecutable, isNull);
      expect(metadata.processCommandPreview, isNull);
      expect(metadata.isEmpty, isTrue);
    });
  });
}
