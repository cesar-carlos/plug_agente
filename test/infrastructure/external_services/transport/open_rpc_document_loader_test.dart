import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/transport/open_rpc_document_loader.dart';

void main() {
  group('OpenRpcDocumentLoader', () {
    test('returns the asset bundle document on first try and caches it', () async {
      var assetCallCount = 0;
      var fileCallCount = 0;
      final loader = OpenRpcDocumentLoader(
        assetLoader: (key) async {
          assetCallCount++;
          return jsonEncode({
            'openrpc': '1.3.2',
            'info': {'title': 'asset', 'version': '1.0'},
            'methods': ['m1'],
          });
        },
        fileLoader: (path) async {
          fileCallCount++;
          throw StateError('should not be called');
        },
        cwdProvider: () => 'C:/cwd',
      );

      final first = await loader.getDocument();
      final second = await loader.getDocument();

      expect(first['info'], isA<Map<String, dynamic>>());
      expect((first['info'] as Map<String, dynamic>)['title'], 'asset');
      expect(identical(first, second), isTrue);
      expect(assetCallCount, 1);
      expect(fileCallCount, 0);
    });

    test('falls back to disk when the asset bundle fails', () async {
      final loader = OpenRpcDocumentLoader(
        assetLoader: (_) => throw StateError('asset missing'),
        fileLoader: (_) async => jsonEncode({
          'openrpc': '1.3.2',
          'info': {'title': 'disk', 'version': '1.0'},
          'methods': ['from_disk'],
        }),
        cwdProvider: () => 'C:/cwd',
      );

      final doc = await loader.getDocument();

      expect((doc['info'] as Map<String, dynamic>)['title'], 'disk');
      expect(doc['methods'], ['from_disk']);
    });

    test('returns minimal fallback when both asset and disk fail', () async {
      final loader = OpenRpcDocumentLoader(
        assetLoader: (_) => throw StateError('asset missing'),
        fileLoader: (_) => throw StateError('disk missing'),
        cwdProvider: () => 'C:/cwd',
      );

      final doc = await loader.getDocument();

      expect(doc['openrpc'], '1.3.2');
      expect(doc['methods'], isEmpty);
      expect(
        (doc['info'] as Map<String, dynamic>)['title'],
        'Plug Agente Socket RPC',
      );
    });

    test('shares an in-flight load across concurrent callers', () async {
      var assetCallCount = 0;
      final loader = OpenRpcDocumentLoader(
        assetLoader: (_) async {
          assetCallCount++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return jsonEncode(<String, dynamic>{
            'openrpc': '1.3.2',
            'info': {'title': 'asset', 'version': '1.0'},
            'methods': <dynamic>[],
          });
        },
        fileLoader: (_) => throw StateError('should not be called'),
        cwdProvider: () => 'C:/cwd',
      );

      final results = await Future.wait([
        loader.getDocument(),
        loader.getDocument(),
        loader.getDocument(),
      ]);

      expect(assetCallCount, 1);
      expect(identical(results[0], results[1]), isTrue);
      expect(identical(results[1], results[2]), isTrue);
    });
  });
}
