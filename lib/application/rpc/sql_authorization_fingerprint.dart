import 'package:plug_agente/core/utils/prepared_sql.dart';

/// Normalizes SQL for client-token authorization deduplication.
///
/// Strips documentation comments, then collapses whitespace and lowercases
/// so equivalent statements share a fingerprint.
String sqlAuthorizationFingerprint(String sql) {
  return PreparedSql.fingerprintFor(sql);
}
