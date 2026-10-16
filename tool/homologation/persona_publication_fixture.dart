import 'package:odbc_fast/odbc_fast.dart' as odbc;

/// Operator-only declarations from the private session manifest, never RPC SQL.
class PublicationFixture {
  PublicationFixture(this.service, this.connectionString, this.database, this.engine, List<dynamic> declarations)
    : tables = declarations.cast<Map<String, dynamic>>() {
    if (!RegExp(r'^se7e_persona_[a-f0-9]{12}_test$').hasMatch(database) ||
        !['postgres', 'mssql', 'sybase'].contains(engine) ||
        tables.length > 16) {
      throw StateError('Invalid private publication fixture.');
    }
    final names = <String>{};
    for (final table in tables) {
      final name = table['table'] as String;
      // Dedicated namespace prevents collision with identity and chain fixtures.
      if (!RegExp(r'^publication_[a-z0-9_]{1,48}$').hasMatch(name) || !names.add(name)) {
        throw StateError('Invalid or duplicate fixture table.');
      }
      final columns = _columns(table);
      final columnNames = <String>{};
      if (columns.isEmpty || columns.length > 100) throw StateError('Invalid fixture columns.');
      for (final column in columns) {
        if (!columnNames.add(column['name'] as String)) throw StateError('Duplicate fixture column.');
        _quote(column['name'] as String);
        _type(column);
        if (column['nullable'] is! bool || column['generated'] is! bool) {
          throw StateError('Explicit column flags required.');
        }
        if (column['generated'] == true && (column['type'] != 'integer' || column['nullable'] == true)) {
          throw StateError('Invalid generated fixture column.');
        }
      }
      if (columns.where((c) => c['generated'] == true).length > 1) throw StateError('Multiple generated columns.');
      for (final check in ((table['checks'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>()) {
        final min = check['min'] as String;
        final max = check['max'] as String;
        if (check['kind'] != 'integer_range' ||
            columns.singleWhere((c) => c['name'] == check['column'])['type'] != 'integer' ||
            !RegExp(r'^-?\d{1,19}$').hasMatch(min) ||
            !RegExp(r'^-?\d{1,19}$').hasMatch(max) ||
            BigInt.parse(min) > BigInt.parse(max) ||
            BigInt.parse(min) < BigInt.parse('-9223372036854775808') ||
            BigInt.parse(max) > BigInt.parse('9223372036854775807')) {
          throw StateError('Invalid private fixture CHECK.');
        }
      }
      for (final key in [table['primaryKey'], ...table['uniqueKeys'] as List<dynamic>]) {
        final parts = (key as List<dynamic>).cast<String>();
        if (parts.isEmpty || parts.toSet().length != parts.length || !columnNames.containsAll(parts)) {
          throw StateError('Invalid fixture key.');
        }
      }
      for (final fk in ((table['foreignKeys'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>()) {
        if (!['no_action', 'cascade'].contains(fk['onUpdate'] ?? 'no_action') ||
            !['no_action', 'cascade'].contains(fk['onDelete'] ?? 'no_action')) {
          throw StateError('Invalid private fixture cascade.');
        }
        final target = tables.takeWhile((t) => t != table).where((t) => t['table'] == fk['targetTable']).single;
        final local = (fk['columns'] as List<dynamic>).cast<String>();
        final remote = (fk['targetColumns'] as List<dynamic>).cast<String>();
        final keys = [target['primaryKey'], ...target['uniqueKeys'] as List<dynamic>];
        if (local.isEmpty ||
            local.toSet().length != local.length ||
            local.length != remote.length ||
            !keys.any((key) => (key as List<dynamic>).join('|') == remote.join('|')) ||
            !local.asMap().entries.every(
              (e) =>
                  columns.singleWhere((c) => c['name'] == e.value)['type'] ==
                  _columns(target).singleWhere((c) => c['name'] == remote[e.key])['type'],
            )) {
          throw StateError('Invalid private fixture FK.');
        }
      }
      final targets = <String>{};
      for (final key in ['insertAudit', 'updateAudit', 'deleteAudit']) {
        final audit = table[key] as Map<String, dynamic>?;
        if (audit != null) {
          final target = tables.singleWhere((t) => t['table'] == audit['targetTable']);
          final remote = _columns(target);
          if (!targets.add(audit['targetTable'] as String) ||
              target == table ||
              target['insertAudit'] != null ||
              target['updateAudit'] != null ||
              target['deleteAudit'] != null ||
              ((target['foreignKeys'] as List<dynamic>?) ?? []).isNotEmpty ||
              columns.any((c) => c['generated'] == true) ||
              remote.length != columns.length ||
              !columns.asMap().entries.every(
                (e) => ['name', 'type', 'nullable', 'generated'].every((key) => e.value[key] == remote[e.key][key]),
              )) {
            throw StateError('Invalid private fixture audit trigger.');
          }
        }
      }
    }
  }

  final odbc.OdbcService service;
  final String connectionString;
  final String database;
  final String engine;
  final List<Map<String, dynamic>> tables;
  bool _poisoned = false;

  List<Map<String, dynamic>> _columns(Map<String, dynamic> table) =>
      (table['columns'] as List<dynamic>).cast<Map<String, dynamic>>();

  String _quote(String value) {
    if (!RegExp(r'^[a-z_][a-z0-9_]{0,62}$').hasMatch(value)) throw StateError('Invalid fixture identifier.');
    return engine == 'mssql' ? '[$value]' : '"$value"';
  }

  String _type(Map<String, dynamic> column) => switch (column['type']) {
    'integer' when column['generated'] == true => switch (engine) {
      'mssql' => 'BIGINT IDENTITY(1,1)',
      'sybase' => 'BIGINT DEFAULT AUTOINCREMENT',
      _ => 'BIGINT GENERATED BY DEFAULT AS IDENTITY',
    },
    'integer' => 'BIGINT',
    'decimal' => 'DECIMAL(28,8)',
    'date' => 'DATE',
    'boolean' => engine == 'postgres' ? 'BOOLEAN' : 'BIT',
    'uuid' => engine == 'postgres' ? 'UUID' : 'UNIQUEIDENTIFIER',
    'string' => engine == 'postgres' ? 'VARCHAR(2000)' : 'NVARCHAR(2000)',
    _ => throw StateError('Unsupported fixture scalar.'),
  };

  Future<void> _connected(Future<void> Function(String) action) async {
    if (_poisoned) throw StateError('Discard uncertain fixture; never retry.');
    final id = (await service.connect(
      connectionString,
      options: const odbc.ConnectionOptions(maxReconnectAttempts: 0),
    )).getOrThrow().id;
    try {
      final actual = (await service.executeQuery(
        engine == 'postgres' ? 'SELECT CURRENT_DATABASE()' : 'SELECT DB_NAME()',
        connectionId: id,
      )).getOrThrow().rows.single.single;
      if (actual != database) throw StateError('Private fixture identity mismatch.');
      await action(id);
    } on Object {
      _poisoned = true;
      rethrow;
    } finally {
      (await service.disconnect(id)).getOrThrow();
    }
  }

  Future<void> _create(String id, Map<String, dynamic> table) async {
    final definitions = [
      for (final c in _columns(table))
        '${_quote(c['name'] as String)} ${_type(c)}${c['nullable'] == true ? '' : ' NOT NULL'}',
      'PRIMARY KEY (${(table['primaryKey'] as List<dynamic>).cast<String>().map(_quote).join(',')})',
      for (final key in table['uniqueKeys'] as List<dynamic>)
        'UNIQUE (${(key as List<dynamic>).cast<String>().map(_quote).join(',')})',
      for (final fk in ((table['foreignKeys'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>())
        'FOREIGN KEY (${(fk['columns'] as List<dynamic>).cast<String>().map(_quote).join(',')}) REFERENCES ${_quote(fk['targetTable'] as String)} (${(fk['targetColumns'] as List<dynamic>).cast<String>().map(_quote).join(',')})${fk['onUpdate'] == 'cascade' ? ' ON UPDATE CASCADE' : ''}${fk['onDelete'] == 'cascade' ? ' ON DELETE CASCADE' : ''}',
      for (final check in ((table['checks'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>())
        'CHECK (${_quote(check['column'] as String)} >= ${check['min']} AND ${_quote(check['column'] as String)} <= ${check['max']})',
    ];
    (await service.executeQuery(
      'CREATE TABLE ${_quote(table['table'] as String)} (${definitions.join(',')})',
      connectionId: id,
    )).getOrThrow();
  }

  Future<void> initialize() => _connected((id) async {
    for (final table in tables) {
      await _create(id, table);
    }
    await _triggers(id);
  });

  Future<void> _triggers(String id) async {
    for (final table in tables) {
      for (final event in ['insert', 'update', 'delete']) {
        final audit = table['${event}Audit'] as Map<String, dynamic>?;
        if (audit == null) continue;
        final name = table['table'] as String;
        final source = _quote(name);
        final target = _quote(audit['targetTable'] as String);
        final columns = _columns(table).map((c) => _quote(c['name'] as String)).toList();
        final list = columns.join(',');
        final values = columns.map((c) => 'n.$c').join(',');
        final trigger = _quote('${name}_a$event');
        final operation = event.toUpperCase();
        final image = event == 'delete' ? 'OLD' : 'NEW';
        if (engine == 'postgres') {
          final function = _quote('${name}_${event}_fn');
          (await service.executeQuery(
            'CREATE OR REPLACE FUNCTION $function() RETURNS trigger LANGUAGE plpgsql AS \$\$ DECLARE n RECORD := $image; BEGIN INSERT INTO $target ($list) VALUES ($values); RETURN $image; END; \$\$',
            connectionId: id,
          )).getOrThrow();
          (await service.executeQuery(
            'CREATE TRIGGER $trigger AFTER $operation ON $source FOR EACH ROW EXECUTE FUNCTION $function()',
            connectionId: id,
          )).getOrThrow();
        } else if (engine == 'mssql') {
          (await service.executeQuery(
            'CREATE TRIGGER $trigger ON $source AFTER $operation AS BEGIN SET NOCOUNT ON; INSERT INTO $target ($list) SELECT $list FROM ${event == 'delete' ? 'deleted' : 'inserted'}; END',
            connectionId: id,
          )).getOrThrow();
        } else {
          (await service.executeQuery(
            'CREATE TRIGGER $trigger AFTER $operation ON $source REFERENCING $image AS n FOR EACH ROW BEGIN INSERT INTO $target ($list) VALUES ($values); END',
            connectionId: id,
          )).getOrThrow();
        }
      }
    }
  }

  // Called only after a confirmed terminal result. Reset identity deterministically.
  Future<void> clear() => _connected((id) async {
    for (final table in tables.reversed) {
      (await service.executeQuery('DROP TABLE ${_quote(table['table'] as String)}', connectionId: id)).getOrThrow();
    }
    for (final table in tables) {
      await _create(id, table);
    }
    await _triggers(id);
  });

  Object _value(Map<String, dynamic> scalar, Map<String, dynamic> column) {
    final value = scalar['value'];
    if (scalar['type'] == 'null' && value == null && column['nullable'] == true) return const odbc.ParamValueNull();
    if (scalar['type'] != column['type']) throw StateError('Fixture scalar type mismatch.');
    return switch (scalar['type']) {
      'integer' when value is String && RegExp(r'^-?\d+$').hasMatch(value) => odbc.ParamValueInt64(int.parse(value)),
      'decimal' when value is String && RegExp(r'^-?\d{1,20}(?:\.\d{1,8})?$').hasMatch(value) => odbc.ParamValueDecimal(
        value,
      ),
      'boolean' when value is bool => value,
      'string' when value is String && value.length <= 2000 => odbc.ParamValueString(value),
      'date' when value is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) => odbc.ParamValueString(value),
      'uuid'
          when value is String && RegExp(r'^[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$').hasMatch(value) =>
        odbc.ParamValueString(value),
      _ => throw StateError('Invalid or inexact fixture scalar.'),
    };
  }

  Future<void> prepare(List<dynamic> seeds) => _connected((id) async {
    if (seeds.length != tables.length) throw StateError('Incomplete fixture seeds.');
    final seen = <String>{};
    for (final item in seeds) {
      final seed = item as Map<String, dynamic>;
      final name = seed['table'] as String;
      if (!seen.add(name)) throw StateError('Duplicate fixture seed.');
      final table = tables.singleWhere((t) => t['table'] == name);
      final count = (await service.executeQuery(
        'SELECT COUNT(*) FROM ${_quote(name)}',
        connectionId: id,
      )).getOrThrow().rows.single.single;
      if (count.toString() != '0') throw StateError('Fixture is not empty; refusing replacement.');
      final columns = _columns(table).where((c) => c['generated'] != true).toList();
      final rows = seed['rows'] as List<dynamic>;
      if (rows.length > 100) throw StateError('Fixture row limit exceeded.');
      for (final item in rows) {
        final row = item as Map<String, dynamic>;
        if (row.length != columns.length || columns.any((c) => !row.containsKey(c['name']))) {
          throw StateError('Incomplete fixture row.');
        }
        final params = {
          for (final c in columns) c['name'] as String: _value(row[c['name']] as Map<String, dynamic>, c),
        };
        (await service.executeQueryNamed(
          id,
          'INSERT INTO ${_quote(name)} (${columns.map((c) => _quote(c['name'] as String)).join(',')}) VALUES (${columns.map((c) => ':${c['name']}').join(',')})',
          params,
        )).getOrThrow();
      }
    }
  });
}
