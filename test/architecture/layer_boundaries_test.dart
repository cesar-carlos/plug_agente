import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('layer boundaries', () {
    test('infrastructure does not import application', () {
      final offenders = <String>[];
      for (final entity in Directory('lib/infrastructure').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final content = entity.readAsStringSync();
        if (content.contains('package:plug_agente/application/')) {
          offenders.add(entity.path);
        }
      }

      expect(offenders, isEmpty);
    });

    test('application and domain do not import forbidden outer dependencies', () {
      final offenders = <String>[];
      for (final root in const <String>['lib/application', 'lib/domain']) {
        for (final entity in Directory(root).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) {
            continue;
          }
          final content = entity.readAsStringSync();
          final forbiddenImports = <String>[
            'package:plug_agente/infrastructure',
            'package:plug_agente/presentation',
            'package:odbc_fast/',
            'package:flutter/',
          ];
          for (final forbiddenImport in forbiddenImports) {
            if (content.contains(forbiddenImport)) {
              offenders.add('${entity.path}: $forbiddenImport');
            }
          }
        }
      }

      expect(offenders, isEmpty);
    });

    test('RPC dispatcher public facade stays free of method logic and infrastructure imports', () {
      final file = File('lib/application/rpc/rpc_method_dispatcher.dart');
      final content = file.readAsStringSync();
      expect(content, isNot(contains('package:plug_agente/infrastructure')));
      expect(content, isNot(contains('RpcMethodDispatcherImplementation')));
      expect(content, isNot(contains("part 'handlers/rpc_method_handlers.dart'")));
      expect(content, isNot(contains('Future<RpcResponse> _handle')));
      expect(content, isNot(contains('_handleSql')));
      expect(content, isNot(contains('_handleAgent')));
      expect(content, isNot(contains('_handleClient')));
      expect(content, isNot(contains('IDatabaseGateway _databaseGateway')));
    });

    test('RPC handlers do not depend on dispatcher internals', () {
      final file = File('lib/application/rpc/handlers/rpc_method_handlers.dart');
      final content = file.readAsStringSync();
      expect(content, isNot(contains('RpcMethodDispatcher')));
      expect(content, isNot(contains('RpcMethodDispatcherImplementation')));
      expect(content, isNot(contains('_DispatcherBackedRpcMethodHandler')));
    });
  });
}
