/// Typed read access to the `sql.execute` RPC params object.
///
/// Keeps string keys and casts in one place at the application boundary.
final class SqlExecuteParamsReader {
  SqlExecuteParamsReader(this._raw);

  final Map<String, dynamic> _raw;

  String? get sql => _raw['sql'] as String?;

  Map<String, dynamic>? get options => _raw['options'] as Map<String, dynamic>?;

  Map<String, dynamic>? get boundParams => _raw['params'] as Map<String, dynamic>?;

  String? get database => _raw['database'] as String?;

  String? get idempotencyKey => _raw['idempotency_key'] as String?;

  dynamic get rawForFingerprint => _raw;
}
