// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';

class FileTokenAuditStore implements ITokenAuditStore {
  FileTokenAuditStore({String? fileName, String? basePath})
    : _fileName = fileName ?? 'token_audit.jsonl',
      _basePath = basePath;

  final String _fileName;
  final String? _basePath;
  String? _cachedDir;

  Future<String> _getAuditDir() async {
    final base = _basePath;
    if (base != null) {
      return base;
    }
    _cachedDir ??= (await getApplicationSupportDirectory()).path;
    return _cachedDir!;
  }

  Future<File> _getAuditFile() async {
    final dir = await _getAuditDir();
    final auditDir = path.join(dir, 'plug_agente', 'audit');
    final dirFile = Directory(auditDir);
    if (!await dirFile.exists()) {
      await dirFile.create(recursive: true);
    }
    return File(path.join(auditDir, _fileName));
  }

  @override
  Future<void> record(TokenAuditEvent event) async {
    try {
      final file = await _getAuditFile();
      final line = '${jsonEncode(event.toJson())}\n';
      await file.writeAsString(line, mode: FileMode.append);
    } on Object catch (e, stackTrace) {
      developer.log(
        'Token audit record failed',
        name: 'file_token_audit_store',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
