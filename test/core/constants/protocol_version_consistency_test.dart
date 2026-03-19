import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:plug_agente/core/constants/protocol_version.dart';

void main() {
  group('ProtocolVersion consistency', () {
    test('openrpc.json info.version should match ProtocolVersion.openRpcVersion',
        () {
      final openRpcPath = path.join(
        Directory.current.path,
        'docs',
        'communication',
        'openrpc.json',
      );
      final file = File(openRpcPath);
      expect(file.existsSync(), isTrue, reason: 'openrpc.json should exist');

      final content = file.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final info = json['info'] as Map<String, dynamic>?;
      expect(info, isNotNull, reason: 'openrpc.json should have info');
      final version = info!['version'] as String?;
      expect(version, isNotNull, reason: 'info should have version');

      expect(
        version,
        equals(ProtocolVersion.openRpcVersion),
        reason:
            'openrpc.json info.version must match ProtocolVersion.openRpcVersion '
            'to avoid drift. Update lib/core/constants/protocol_version.dart '
            'or docs/communication/openrpc.json.',
      );
    });
  });
}
