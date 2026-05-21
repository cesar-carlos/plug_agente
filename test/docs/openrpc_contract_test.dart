import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/infrastructure/external_services/transport/open_rpc_document_loader.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

String _openRpcSchemaRef(String schemaFileName) => './schemas/$schemaFileName';

/// Published params/result schema refs per `agent.action.*` method (MVP wire).
/// Paths are derived from [TransportSchemaIds] so OpenRPC stays aligned with the schema bundle.
Map<String, ({String paramsSchema, String resultSchema})> get _agentActionOpenRpcSchemaRefs =>
    <String, ({String paramsSchema, String resultSchema})>{
      AgentActionRpcConstants.agentActionRunRpcMethodName: (
        paramsSchema: _openRpcSchemaRef(TransportSchemaIds.paramsAgentActionRun),
        resultSchema: _openRpcSchemaRef(TransportSchemaIds.resultAgentActionGetExecution),
      ),
      AgentActionRpcConstants.agentActionValidateRunRpcMethodName: (
        paramsSchema: _openRpcSchemaRef(TransportSchemaIds.paramsAgentActionValidateRun),
        resultSchema: _openRpcSchemaRef(TransportSchemaIds.resultAgentActionValidateRun),
      ),
      AgentActionRpcConstants.agentActionCancelRpcMethodName: (
        paramsSchema: _openRpcSchemaRef(TransportSchemaIds.paramsAgentActionCancel),
        resultSchema: _openRpcSchemaRef(TransportSchemaIds.resultAgentActionCancel),
      ),
      AgentActionRpcConstants.agentActionGetExecutionRpcMethodName: (
        paramsSchema: _openRpcSchemaRef(TransportSchemaIds.paramsAgentActionGetExecution),
        resultSchema: _openRpcSchemaRef(TransportSchemaIds.resultAgentActionGetExecution),
      ),
    };

const Set<String> _publishedAgentActionSchemaFiles = <String>{
  TransportSchemaIds.paramsAgentActionRun,
  TransportSchemaIds.paramsAgentActionValidateRun,
  TransportSchemaIds.paramsAgentActionCancel,
  TransportSchemaIds.paramsAgentActionGetExecution,
  TransportSchemaIds.resultAgentActionGetExecution,
  TransportSchemaIds.resultAgentActionValidateRun,
  TransportSchemaIds.resultAgentActionCancel,
};

Map<String, dynamic> _readOpenRpcFromDisk() {
  final openrpcFile = File('docs/communication/openrpc.json');
  expect(openrpcFile.existsSync(), isTrue, reason: 'Run tests from repo root');
  return jsonDecode(openrpcFile.readAsStringSync()) as Map<String, dynamic>;
}

Map<String, dynamic>? _openRpcMethodByName(
  Map<String, dynamic> document,
  String methodName,
) {
  final methods = document['methods'] as List<dynamic>?;
  if (methods == null) {
    return null;
  }
  for (final dynamic entry in methods) {
    final method = entry as Map<String, dynamic>;
    if (method['name'] == methodName) {
      return method;
    }
  }
  return null;
}

String? _schemaRefFromMethodParam(Map<String, dynamic> method) {
  final params = method['params'] as List<dynamic>?;
  if (params == null || params.isEmpty) {
    return null;
  }
  final first = params.first as Map<String, dynamic>;
  final schema = first['schema'] as Map<String, dynamic>?;
  return schema?[r'$ref'] as String?;
}

String? _schemaRefFromMethodResult(Map<String, dynamic> method) {
  final result = method['result'] as Map<String, dynamic>?;
  final schema = result?['schema'] as Map<String, dynamic>?;
  return schema?[r'$ref'] as String?;
}

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

        final decoded = _readOpenRpcFromDisk();
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

    test('OpenRPC agent.action.* methods should match published contract set', () {
      final decoded = _readOpenRpcFromDisk();
      final methods = decoded['methods'] as List<dynamic>;
      final names = methods.map((dynamic m) => (m as Map<String, dynamic>)['name'] as String).toSet();

      final agentActionNames = names
          .where((String n) => n.startsWith(AgentActionRpcConstants.remoteAgentActionMethodPrefix))
          .toSet();
      expect(agentActionNames, AgentActionRpcConstants.remotePublishedRpcMethodNames);
    });

    test('OpenRPC should list agent.action.* methods in stable published order', () {
      final decoded = _readOpenRpcFromDisk();
      final methods = decoded['methods'] as List<dynamic>;
      final orderedAgentActionNames = <String>[
        for (final dynamic entry in methods)
          if (_isPublishedAgentActionRpcMethodName(
            (entry as Map<String, dynamic>)['name'] as String,
          ))
            entry['name'] as String,
      ];
      expect(orderedAgentActionNames, AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered);
    });

    test('OpenRPC should reference every published agent.action schema file', () {
      final decoded = _readOpenRpcFromDisk();
      final refs = <String>{};
      _collectLocalRefs(decoded, refs);

      final referencedSchemaFiles = refs
          .where((String ref) => ref.startsWith('./schemas/rpc.'))
          .map((String ref) => ref.substring('./schemas/'.length))
          .where(_publishedAgentActionSchemaFiles.contains)
          .toSet();

      expect(referencedSchemaFiles, _publishedAgentActionSchemaFiles);
    });

    test('should wire each published agent.action.* method to params and result schemas', () {
      final decoded = _readOpenRpcFromDisk();
      for (final methodName in AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered) {
        final expected = _agentActionOpenRpcSchemaRefs[methodName];
        expect(expected, isNotNull, reason: 'missing schema ref map for $methodName');

        final method = _openRpcMethodByName(decoded, methodName);
        expect(method, isNotNull, reason: 'OpenRPC missing method $methodName');
        expect(method!['paramStructure'], 'by-name');

        expect(_schemaRefFromMethodParam(method), expected!.paramsSchema);
        expect(_schemaRefFromMethodResult(method), expected.resultSchema);
      }
    });

    test('agent.action.run should reuse getExecution result schema in MVP', () {
      final run = _agentActionOpenRpcSchemaRefs[AgentActionRpcConstants.agentActionRunRpcMethodName]!;
      final getExecution =
          _agentActionOpenRpcSchemaRefs[AgentActionRpcConstants.agentActionGetExecutionRpcMethodName]!;
      expect(run.resultSchema, getExecution.resultSchema);
    });

    test(
      'OpenRpcDocumentLoader should expose the same agent.action.* methods as the contract set',
      () async {
        final loader = OpenRpcDocumentLoader();
        final decoded = await loader.getDocument();
        final methods = decoded['methods'] as List<dynamic>?;
        expect(methods, isNotNull, reason: 'OpenRPC document should list methods');
        final names = methods!.map((dynamic m) => (m as Map<String, dynamic>)['name'] as String).toSet();
        final agentActionNames = names
            .where((String n) => n.startsWith(AgentActionRpcConstants.remoteAgentActionMethodPrefix))
            .toSet();
        expect(agentActionNames, AgentActionRpcConstants.remotePublishedRpcMethodNames);

        for (final methodName in AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered) {
          final method = _openRpcMethodByName(decoded, methodName);
          expect(method, isNotNull, reason: 'loader document missing $methodName');
          final expected = _agentActionOpenRpcSchemaRefs[methodName]!;
          expect(_schemaRefFromMethodParam(method!), expected.paramsSchema);
          expect(_schemaRefFromMethodResult(method), expected.resultSchema);
        }
      },
    );
  });
}

bool _isPublishedAgentActionRpcMethodName(String methodName) =>
    methodName.startsWith(AgentActionRpcConstants.remoteAgentActionMethodPrefix);

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
