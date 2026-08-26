import 'package:plug_agente/core/utils/split_sql_statements.dart';
import 'package:plug_agente/core/utils/strip_sql_comments.dart';

/// One parse of a SQL request: original text plus comment-stripped form.
///
/// The database still receives [raw]; [stripped] is only for validation,
/// classification, streaming policy, and authorization fingerprints.
class PreparedSql {
  PreparedSql._({
    required this.raw,
    required this.trimmed,
    required this.stripped,
    required this.fingerprint,
    required this.hasMultipleStatements,
  });

  factory PreparedSql.parse(String raw) {
    final trimmed = raw.trim();
    final stripped = stripTopLevelSqlComments(trimmed).trim();
    return PreparedSql._(
      raw: raw,
      trimmed: trimmed,
      stripped: stripped,
      fingerprint: fingerprintForStripped(stripped),
      hasMultipleStatements: sqlHasMultipleTopLevelStatements(trimmed),
    );
  }

  final String raw;
  final String trimmed;
  final String stripped;
  final String fingerprint;
  final bool hasMultipleStatements;

  static final RegExp _whitespace = RegExp(r'\s+');

  static String fingerprintFor(String sql) {
    return fingerprintForStripped(stripTopLevelSqlComments(sql.trim()).trim());
  }

  static String fingerprintForStripped(String stripped) {
    return stripped.replaceAll(_whitespace, ' ').toLowerCase();
  }
}
