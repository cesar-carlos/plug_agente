import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as path;
import 'package:plug_agente/core/logger/app_logger.dart';

/// Identifiers of the JSON Schemas bundled under
/// `docs/communication/schemas/*.json` (kept in sync with the directory).
class TransportSchemaIds {
  TransportSchemaIds._();

  static const String payloadFrame = 'payload-frame.schema.json';
  static const String rpcRequest = 'rpc.request.schema.json';
  static const String rpcResponse = 'rpc.response.schema.json';
  static const String rpcError = 'rpc.error.schema.json';
  static const String rpcBatchRequest = 'rpc.batch.request.schema.json';
  static const String rpcBatchResponse = 'rpc.batch.response.schema.json';
  static const String agentRegister = 'agent.register.schema.json';
  static const String agentCapabilities = 'agent.capabilities.schema.json';
  static const String agentReady = 'agent.ready.schema.json';
  static const String agentProfile = 'agent.profile.schema.json';
  static const String paramsSqlExecute = 'rpc.params.sql-execute.schema.json';
  static const String paramsSqlExecuteBatch = 'rpc.params.sql-execute-batch.schema.json';
  static const String paramsSqlCancel = 'rpc.params.sql-cancel.schema.json';
  static const String paramsAgentGetProfile = 'rpc.params.agent-get-profile.schema.json';
  static const String paramsAgentGetHealth = 'rpc.params.agent-get-health.schema.json';
  static const String paramsClientTokenGetPolicy = 'rpc.params.client-token-get-policy.schema.json';
  static const String resultSqlExecute = 'rpc.result.sql-execute.schema.json';
  static const String resultSqlExecuteBatch = 'rpc.result.sql-execute-batch.schema.json';
  static const String resultAgentGetProfile = 'rpc.result.agent-get-profile.schema.json';
  static const String resultAgentGetHealth = 'rpc.result.agent-get-health.schema.json';
  static const String resultClientTokenGetPolicy = 'rpc.result.client-token-get-policy.schema.json';
  static const String streamChunk = 'rpc.stream.chunk.schema.json';
  static const String streamComplete = 'rpc.stream.complete.schema.json';
  static const String streamPull = 'rpc.stream.pull.schema.json';

  static const List<String> all = [
    payloadFrame,
    rpcRequest,
    rpcResponse,
    rpcError,
    rpcBatchRequest,
    rpcBatchResponse,
    agentRegister,
    agentCapabilities,
    agentReady,
    agentProfile,
    paramsSqlExecute,
    paramsSqlExecuteBatch,
    paramsSqlCancel,
    paramsAgentGetProfile,
    paramsAgentGetHealth,
    paramsClientTokenGetPolicy,
    resultSqlExecute,
    resultSqlExecuteBatch,
    resultAgentGetProfile,
    resultAgentGetHealth,
    resultClientTokenGetPolicy,
    streamChunk,
    streamComplete,
    streamPull,
  ];
}

/// Loads JSON Schemas from `docs/communication/schemas/` (asset bundle in
/// production, file system fallback in dev/headless tests). Once loaded each
/// schema is cached and exposed by short identifier (the file name).
///
/// The loader resolves cross-schema `$ref` lookups by registering every
/// loaded schema in a `SchemaRegistry` so references like
/// `./agent.profile.schema.json` resolve without network access.
class TransportSchemaLoader {
  TransportSchemaLoader({
    Future<String> Function(String key)? assetLoader,
    Future<String> Function(String filePath)? fileLoader,
    String Function()? cwdProvider,
  }) : _assetLoader = assetLoader ?? rootBundle.loadString,
       _fileLoader = fileLoader ?? _defaultFileLoader,
       _cwdProvider = cwdProvider ?? _defaultCwdProvider;

  static const String _assetPrefix = 'docs/communication/schemas/';

  final Future<String> Function(String key) _assetLoader;
  final Future<String> Function(String filePath) _fileLoader;
  final String Function() _cwdProvider;

  final Map<String, JsonSchema> _schemas = {};
  Future<void>? _loadAllFuture;

  /// Loads every schema in [TransportSchemaIds.all]. Idempotent: subsequent
  /// calls reuse the same future. Failures for individual schemas are logged
  /// and the schema is skipped (other validations continue to work).
  Future<void> loadAll() {
    return _loadAllFuture ??= _loadAllInternal();
  }

  /// Returns the loaded schema for [id] or `null` when it hasn't been loaded
  /// (either because [loadAll] hasn't been awaited or because the asset
  /// failed to load).
  JsonSchema? get(String id) => _schemas[id];

  Iterable<String> get loadedIds => _schemas.keys;

  Future<void> _loadAllInternal() async {
    // First pass: read all source bytes so we can resolve local `$ref`s
    // synchronously via a [RefProvider]. Done in a separate pass because
    // [JsonSchema.create] needs the provider to be ready before it inspects
    // schemas that reference siblings (e.g. rpc.response -> rpc.error).
    final rawById = <String, Object>{};
    for (final id in TransportSchemaIds.all) {
      try {
        final content = await _readSchemaContent(id);
        rawById[id] = jsonDecode(content) as Object;
      } on Object catch (e, stack) {
        AppLogger.warning('Failed to read JSON Schema $id: $e', e, stack);
      }
    }
    final refProvider = RefProvider.sync((String ref) {
      final segment = Uri.tryParse(ref)?.pathSegments.lastOrNull;
      if (segment == null) return null;
      final raw = rawById[segment];
      if (raw is Map<String, dynamic>) return raw;
      return null;
    });

    final pending = <String>[];
    for (final entry in rawById.entries) {
      try {
        final schema = JsonSchema.create(entry.value, refProvider: refProvider);
        _schemas[entry.key] = schema;
      } on Object catch (e, stack) {
        AppLogger.warning(
          'Failed to compile JSON Schema ${entry.key}: $e',
          e,
          stack,
        );
        pending.add(entry.key);
      }
    }
    if (pending.isNotEmpty) {
      AppLogger.warning(
        'Skipped ${pending.length} schemas during boot: ${pending.join(', ')}',
      );
    }
  }

  Future<String> _readSchemaContent(String id) async {
    try {
      return await _assetLoader('$_assetPrefix$id');
    } on Object {
      final filePath = path.join(
        _cwdProvider(),
        'docs',
        'communication',
        'schemas',
        id,
      );
      return _fileLoader(filePath);
    }
  }

  static Future<String> _defaultFileLoader(String filePath) {
    return File(filePath).readAsString();
  }

  static String _defaultCwdProvider() => Directory.current.path;
}
