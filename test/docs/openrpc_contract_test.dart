import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpenRPC contract files', () {
    test(
      r'should resolve every local schema $ref under docs/communication',
      () {
        final commDir = Directory('docs/communication');
        expect(
          commDir.existsSync(),
          isTrue,
          reason: 'Run tests from repo root',
        );

        final openrpcFile = File('docs/communication/openrpc.json');
        expect(openrpcFile.existsSync(), isTrue);

        final decoded = jsonDecode(openrpcFile.readAsStringSync());
        final refs = <String>{};
        _collectLocalRefs(decoded, refs);

        for (final ref in refs) {
          expect(
            ref.startsWith('./'),
            isTrue,
            reason: 'Only relative ./ refs are validated: $ref',
          );
          final target = File('${commDir.path}/${ref.substring(2)}');
          expect(
            target.existsSync(),
            isTrue,
            reason: 'Missing schema for \$ref $ref',
          );
        }

        expect(refs, isNotEmpty, reason: 'Expected at least one ./schemas ref');
      },
    );
  });
}

void _collectLocalRefs(Object? node, Set<String> sink) {
  if (node is Map) {
    node.forEach((key, value) {
      if (key == r'$ref' && value is String && value.startsWith('./')) {
        sink.add(value);
      }
      _collectLocalRefs(value, sink);
    });
  } else if (node is List) {
    for (final e in node) {
      _collectLocalRefs(e, sink);
    }
  }
}
