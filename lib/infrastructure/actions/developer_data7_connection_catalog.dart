import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/core/constants/agent_action_developer_data7_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_path_normalizer.dart';
import 'package:result_dart/result_dart.dart';
import 'package:xml/xml.dart';

typedef DeveloperData7ConfigReader = Future<String> Function(String path);

class DeveloperData7ConnectionInfo {
  const DeveloperData7ConnectionInfo({
    required this.id,
    required this.label,
    required this.snapshotHash,
  });

  final String id;
  final String label;
  final String snapshotHash;
}

class DeveloperData7ConnectionCatalogSnapshot {
  const DeveloperData7ConnectionCatalogSnapshot({
    required this.connections,
  });

  final List<DeveloperData7ConnectionInfo> connections;

  DeveloperData7ConnectionInfo? findById(String id) {
    final normalizedId = _normalizeConnectionId(id);
    if (normalizedId.isEmpty) {
      return null;
    }

    for (final connection in connections) {
      if (_normalizeConnectionId(connection.id) == normalizedId) {
        return connection;
      }
    }
    return null;
  }
}

class DeveloperData7ConnectionCatalog {
  DeveloperData7ConnectionCatalog({
    DeveloperData7ConfigReader? readConfig,
  }) : _readConfig = readConfig ?? _defaultReadConfig;

  final DeveloperData7ConfigReader _readConfig;

  Future<Result<DeveloperData7ConnectionCatalogSnapshot>> load({
    required String actionId,
    required String configPath,
    required String phase,
  }) async {
    try {
      final xmlText = await _readConfig(configPath);
      return _parse(
        actionId: actionId,
        configPath: configPath,
        phase: phase,
        xmlText: xmlText,
      );
    } on FileSystemException catch (error) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Developer Data7 configuration file could not be read.',
          cause: error,
          code: 'DEVELOPER_DATA7_CONFIG_READ_FAILED',
          context: {
            'action_id': actionId,
            'field': 'data7ConfigPath',
            'phase': phase,
            'path': configPath,
            'reason': AgentActionDeveloperData7Constants.developerData7ConfigReadFailedReason,
            'user_message': 'Nao foi possivel ler o arquivo Data7.Config informado.',
          },
        ),
      );
    }
  }

  Result<DeveloperData7ConnectionCatalogSnapshot> _parse({
    required String actionId,
    required String configPath,
    required String phase,
    required String xmlText,
  }) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xmlText);
    } on XmlException catch (error) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Developer Data7 configuration file is invalid XML.',
          cause: error,
          code: 'DEVELOPER_DATA7_CONFIG_INVALID',
          context: {
            'action_id': actionId,
            'field': 'data7ConfigPath',
            'phase': phase,
            'path': configPath,
            'reason': AgentActionDeveloperData7Constants.developerData7ConfigInvalidReason,
            'user_message':
                'O arquivo Data7.Config informado nao contem um XML valido. O formato esperado usa itens <Item ID="..."> com Descricao/Descrição e Conexao/Conexão.',
          },
        ),
      );
    }

    final items = document.findAllElements('Item');
    final connections = <DeveloperData7ConnectionInfo>[];
    final seenIds = <String>{};
    for (final item in items) {
      final rawId = item.getAttribute('ID')?.trim() ?? '';
      final normalizedId = _normalizeConnectionId(rawId);
      if (normalizedId.isEmpty) {
        continue;
      }
      if (!seenIds.add(normalizedId)) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Developer Data7 configuration has duplicated connection IDs.',
            code: 'DEVELOPER_DATA7_CONNECTION_DUPLICATED',
            context: {
              'action_id': actionId,
              'field': 'connectionId',
              'phase': phase,
              'path': configPath,
              'connection_id': rawId,
              'reason': AgentActionDeveloperData7Constants.developerData7ConnectionDuplicatedReason,
              'user_message': 'O arquivo Data7.Config possui IDs de conexao duplicados.',
            },
          ),
        );
      }

      final label = _firstChildText(item, const ['Descri\u00e7\u00e3o', 'Descricao']) ?? rawId;
      final server = _nestedChildText(item, const ['Conex\u00e3o', 'Conexao'], const ['Servidor']) ?? '';
      final database = _nestedChildText(item, const ['Conex\u00e3o', 'Conexao'], const ['BaseDados']) ?? '';
      final port = _nestedChildText(item, const ['Conex\u00e3o', 'Conexao'], const ['Porta']) ?? '';
      final rdbms = _nestedChildText(item, const ['Conex\u00e3o', 'Conexao'], const ['RDBMS']) ?? '';

      connections.add(
        DeveloperData7ConnectionInfo(
          id: rawId,
          label: label.trim().isEmpty ? rawId : label.trim(),
          snapshotHash: _snapshotHash(
            id: normalizedId,
            label: label,
            server: server,
            database: database,
            port: port,
            rdbms: rdbms,
          ),
        ),
      );
    }

    if (connections.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Developer Data7 configuration does not expose any connection item.',
          code: 'DEVELOPER_DATA7_CONNECTION_MISSING',
          context: {
            'action_id': actionId,
            'field': 'connectionId',
            'phase': phase,
            'path': configPath,
            'reason': AgentActionDeveloperData7Constants.developerData7ConnectionMissingReason,
            'user_message':
                'O arquivo Data7.Config nao possui conexoes disponiveis. Verifique se o XML contem itens <Item ID="..."> com Descricao/Descrição e Conexao/Conexão.',
          },
        ),
      );
    }

    return Success(
      DeveloperData7ConnectionCatalogSnapshot(
        connections: List<DeveloperData7ConnectionInfo>.unmodifiable(connections),
      ),
    );
  }

  String _snapshotHash({
    required String id,
    required String label,
    required String server,
    required String database,
    required String port,
    required String rdbms,
  }) {
    final payload = jsonEncode(<String, String>{
      'id': id.trim(),
      'label': label.trim(),
      'server': server.trim(),
      'database': database.trim(),
      'port': port.trim(),
      'rdbms': rdbms.trim(),
    });
    return 'sha256:${sha256.convert(utf8.encode(payload))}';
  }

  String? _firstChildText(XmlElement element, List<String> names) {
    for (final child in element.childElements) {
      if (names.contains(child.name.local)) {
        return child.innerText;
      }
    }
    return null;
  }

  String? _nestedChildText(
    XmlElement element,
    List<String> parentNames,
    List<String> childNames,
  ) {
    for (final child in element.childElements) {
      if (!parentNames.contains(child.name.local)) {
        continue;
      }
      return _firstChildText(child, childNames);
    }
    return null;
  }

  static Future<String> _defaultReadConfig(String path) async {
    final ioPath = WindowsActionPathNormalizer.forLocalIo(path);
    final bytes = await File(ioPath).readAsBytes();
    return _decodeConfigText(bytes);
  }

  static String _decodeConfigText(List<int> bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }

    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }
}

String _normalizeConnectionId(String value) {
  return value.trim().toUpperCase();
}
