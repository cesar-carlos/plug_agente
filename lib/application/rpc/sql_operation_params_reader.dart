import 'dart:convert';
import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';
import 'package:plug_agente/domain/entities/expected_source.dart';
import 'package:plug_agente/domain/entities/expected_structure.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:uuid/uuid.dart';

/// Strict contract-v1 decoding; content digest is calculated locally, never supplied by the caller.
class SqlOperationParamsReader {
  const SqlOperationParamsReader();
  SqlOperationReference reference(Object? raw, {bool execution = false}) {
    final p = _object(raw);
    _keys(p, {
      'contractVersion',
      'operationId',
      'fingerprint',
      'sourcePhysicalId',
      'expectedSource',
      'database',
      'client_token',
      'clientToken',
      'auth',
      if (execution) ...{'steps', 'maxAffectedRows', 'timeoutMs', 'expectedStructure'},
    });
    if (p['contractVersion'] != 1 || !Uuid.isValidUUID(fromString: _string(p['operationId']))) _invalid();
    final aliases = [p['client_token'], p['clientToken'], p['auth']].where((v) => v != null).toList();
    if (aliases.any((v) => v is! String || v.isEmpty || v.length > 65536) || aliases.toSet().length > 1) _invalid();
    for (final key in ['fingerprint', 'sourcePhysicalId']) {
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(_string(p[key]))) _invalid();
    }
    final db = _string(p['database']);
    if (db.length > 200 || db.trim() != db || RegExp(r'[;{}\r\n\x00]').hasMatch(db)) _invalid();
    return SqlOperationReference(
      operationId: p['operationId'] as String,
      fingerprint: p['fingerprint'] as String,
      sourcePhysicalId: p['sourcePhysicalId'] as String,
      database: db,
      expectedSource: p.containsKey('expectedSource') ? ExpectedSource.fromJson(p['expectedSource']) : null,
    );
  }

  SqlOperationPlan plan(Object? raw) {
    final ref = reference(raw, execution: true);
    final p = _object(raw);
    if (p.containsKey('expectedStructure') && ref.expectedSource == null) _invalid();
    if (utf8.encode(jsonEncode(p)).length > 2 * 1024 * 1024) _invalid();
    final max = _integer(p['maxAffectedRows'], 1, 100000);
    final timeout = _integer(p['timeoutMs'], 1, 300000);
    final rawSteps = p['steps'];
    if (rawSteps is! List || rawSteps.isEmpty || rawSteps.length > 32) _invalid();
    final steps = <SqlOperationStep>[];
    final previous = <String, SqlOperationStep>{};
    for (final rawStep in rawSteps) {
      final s = _object(rawStep);
      _keys(s, {'id', 'effect', 'sql', 'params', 'outputs', 'affectedRows', 'expectedRows'});
      final id = _name(s['id']);
      if (previous.containsKey(id)) _invalid();
      final effect = SqlOperationEffect.values.where((e) => e.name == s['effect']).firstOrNull;
      if (effect == null) _invalid();
      final sql = _string(s['sql']);
      if (utf8.encode(sql).length > 1024 * 1024) _invalid();
      final params = <String, SqlOperationBinding>{};
      for (final entry in _object(s['params']).entries) {
        final name = _name(entry.key);
        final b = _object(entry.value);
        if (b['kind'] == 'value') {
          _keys(b, {'kind', 'scalar'});
          final value = _object(b['scalar']);
          _keys(value, {'type', 'value'});
          if (!value.containsKey('value')) _invalid();
          params[name] = SqlOperationValue(_scalar(value));
        } else if (b['kind'] == 'step_output') {
          _keys(b, {'kind', 'stepId', 'output'});
          final origin = _name(b['stepId']);
          final output = _name(b['output']);
          if (!(previous[origin]?.outputs.containsKey(output) ?? false)) _invalid();
          params[name] = SqlOperationOutput(origin, output);
        } else {
          _invalid();
        }
      }
      final outputs = <String, SqlScalarType>{};
      for (final entry in _object(s['outputs']).entries) {
        outputs[_name(entry.key)] = _type(entry.value);
      }
      final affected = s['affectedRows'] == null ? null : _bounds(s['affectedRows']);
      final expected = s['expectedRows'] == null ? null : _bounds(s['expectedRows']);
      if (effect != SqlOperationEffect.select && (affected == null || affected.max < 1 || affected.max > max)) {
        _invalid();
      }
      if (effect == SqlOperationEffect.select && affected != null) _invalid();
      final step = SqlOperationStep(
        id: id,
        effect: effect,
        sql: sql,
        params: Map.unmodifiable(params),
        outputs: Map.unmodifiable(outputs),
        affectedRows: affected,
        expectedRows: expected,
      );
      previous[id] = step;
      steps.add(step);
    }
    if (steps.every((s) => s.effect == SqlOperationEffect.select)) _invalid();
    final executionContent = Map<String, dynamic>.from(p)
      ..remove('client_token')
      ..remove('clientToken')
      ..remove('auth');
    return SqlOperationPlan(
      operationId: ref.operationId,
      fingerprint: ref.fingerprint,
      sourcePhysicalId: ref.sourcePhysicalId,
      database: ref.database,
      expectedSource: ref.expectedSource,
      expectedStructure: p.containsKey('expectedStructure') ? ExpectedStructure.fromJson(p['expectedStructure']) : null,
      steps: List.unmodifiable(steps),
      maxAffectedRows: max,
      timeout: Duration(milliseconds: timeout),
      contentHash: buildIdempotencyFingerprintForEnvelope(executionContent),
    );
  }

  static SqlScalar _scalar(Map<String, dynamic> raw) {
    final type = _type(raw['type']);
    final value = raw['value'];
    switch (type) {
      case SqlScalarType.integer:
        if (value is! String || !RegExp(r'^-?\d+$').hasMatch(value) || value.length > 32) _invalid();
        final n = BigInt.parse(value);
        if (n < BigInt.parse('-9223372036854775808') || n > BigInt.parse('9223372036854775807')) _invalid();
      case SqlScalarType.decimal:
        if (value is! String || value.length > 128 || !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) _invalid();
      case SqlScalarType.string:
        if (value is! String || value.length > 65536) _invalid();
      case SqlScalarType.uuid:
        if (value is! String || !Uuid.isValidUUID(fromString: value)) _invalid();
      case SqlScalarType.date:
        if (value is! String ||
            !RegExp(
              r'^\d{4}-\d{2}-\d{2}(T(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d+)?)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d))?$',
            ).hasMatch(value) ||
            DateTime.tryParse(value) == null ||
            !_validCalendarDate(value)) {
          _invalid();
        }
      case SqlScalarType.boolean:
        if (value is! bool) _invalid();
      case SqlScalarType.nullValue:
        if (value != null) _invalid();
    }
    return SqlScalar(type, value);
  }

  static bool _validCalendarDate(String value) {
    final day = value.substring(0, 10);
    final parsed = DateTime.tryParse(day);
    return parsed != null && parsed.toIso8601String().startsWith(day);
  }

  static SqlScalarType _type(Object? value) {
    if (value == 'null') return SqlScalarType.nullValue;
    return SqlScalarType.values.where((t) => t.name == value).firstOrNull ?? _invalid();
  }

  static SqlRowBounds _bounds(Object? raw) {
    final b = _object(raw);
    _keys(b, {'min', 'max'});
    final min = _integer(b['min'], 0, 100000);
    final max = _integer(b['max'], 0, 100000);
    if (min > max) _invalid();
    return SqlRowBounds(min, max);
  }

  static Map<String, dynamic> _object(Object? raw) {
    if (raw is! Map || raw.keys.any((key) => key is! String)) _invalid();
    return Map<String, dynamic>.from(raw);
  }

  static void _keys(Map<String, dynamic> raw, Set<String> allowed) {
    if (raw.keys.any((k) => !allowed.contains(k))) _invalid();
  }

  static int _integer(Object? raw, int min, int max) {
    if (raw is! int || raw < min || raw > max) _invalid();
    return raw;
  }

  static String _name(Object? raw) {
    final name = _string(raw);
    if (name.length > 100 || !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) _invalid();
    return name;
  }

  static String _string(Object? raw) {
    if (raw is! String || raw.isEmpty) _invalid();
    return raw;
  }

  static Never _invalid() =>
      throw SqlOperationFailure(code: 'SQL_OPERATION_INVALID', message: 'Invalid SQL operation contract-v1 envelope.');
}
