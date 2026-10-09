// ignore_for_file: avoid_slow_async_io

import 'dart:async';
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
  static const _maxBatchRecords = 64;
  Future<void> _writeTail = Future.value();
  _AuditBatch? _collectingBatch;

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
    // Capture metadata at submission; encoding errors belong to this caller.
    final line = '${jsonEncode(event.toJson())}\n';
    final batch = _collectingBatch ??= _startBatch();
    batch.lines.add(line);
    if (batch.lines.length >= _maxBatchRecords) _collectingBatch = null;
    await batch.written;
  }

  _AuditBatch _startBatch() {
    final previous = _writeTail;
    final released = Completer<void>();
    _writeTail = released.future;
    final batch = _AuditBatch();
    batch.written = _recordAfter(previous, batch, released);
    return batch;
  }

  Future<void> _recordAfter(Future<void> previous, _AuditBatch batch, Completer<void> released) async {
    await previous;
    if (identical(_collectingBatch, batch)) _collectingBatch = null;
    try {
      await _append(batch.lines.join());
    } finally {
      // Keep the queue usable even when the caller observes a programming error.
      released.complete();
    }
  }

  Future<void> _append(String lines) async {
    try {
      final file = await _getAuditFile();
      await file.writeAsString(lines, mode: FileMode.append);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Token audit record failed',
        name: 'file_token_audit_store',
        level: 900,
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
    }
  }
}

class _AuditBatch {
  final List<String> lines = [];
  late final Future<void> written;
}
