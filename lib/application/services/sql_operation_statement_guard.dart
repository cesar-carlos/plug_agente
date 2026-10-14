import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/core/utils/prepared_sql.dart';
import 'package:plug_agente/core/utils/sql_text_scanner.dart';
import 'package:plug_agente/domain/entities/sql_operation_plan.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';

/// Conservative subset for transactional operations, additional to published scope and token policy.
class SqlOperationStatementGuard {
  const SqlOperationStatementGuard();
  void validate(SqlOperationStep step) {
    final prepared = PreparedSql.parse(step.sql);
    if (prepared.hasMultipleStatements) _deny();
    final code = StringBuffer();
    scanSqlText(
      step.sql,
      onCode: (start, end) => code.write(step.sql.substring(start, end)),
      onLiteral: (start, end) {
        final literal = step.sql.substring(start, end);
        final quote = literal.startsWith('[') ? ']' : literal[0];
        if (literal.length < 2 || !literal.endsWith(quote) || literal.contains(r'\')) _deny();
        if (!literal.startsWith("'") &&
            literal.substring(1, literal.length - 1).toLowerCase() == 'se7e_source_identity') {
          _deny();
        }
        // Quotes remain opaque identifiers, never executable keywords or functions.
        code.write(literal.startsWith("'") ? ' __literal ' : ' __identifier ');
      },
      onComment: (_, _, {required isBlock}) => _deny(),
    );
    final text = code.toString().toLowerCase();
    if (RegExp(r'[;$@`#\\]').hasMatch(text) || text.contains('::')) _deny();
    final words = RegExp('[a-z_][a-z0-9_]*').allMatches(text).map((m) => m.group(0)!).toList();
    if (words.isEmpty || words.first != step.effect.name) _deny();
    const forbidden = {
      'se7e_source_identity',
      'create',
      'alter',
      'drop',
      'truncate',
      'grant',
      'revoke',
      'execute',
      'exec',
      'call',
      'do',
      'begin',
      'commit',
      'rollback',
      'savepoint',
      'merge',
      'upsert',
      'copy',
      'load',
      'unload',
      'attach',
      'detach',
      'openrowset',
      'openquery',
      'opendatasource',
      'dblink',
      'nextval',
      'setval',
      'set_config',
      'with',
      'union',
      'intersect',
      'except',
      'limit',
      'offset',
      'fetch',
      'top',
      'first',
      'skip',
      'returning_into',
    };
    if (words.any(forbidden.contains)) _deny();
    // V1 writes target one table. Auxiliary reads are separate typed steps;
    // do not inherit the legacy classifier's mixed UPDATE/DELETE source rules.
    if (step.effect != SqlOperationEffect.select &&
        (words.any({'select', 'join', 'apply', 'using'}.contains) ||
            words.where((w) => w == 'from').length > (step.effect == SqlOperationEffect.delete ? 1 : 0))) {
      _deny();
    }
    for (var i = 1; i < words.length; i++) {
      if ({'insert', 'update', 'delete'}.contains(words[i])) _deny();
    }
    if (step.effect == SqlOperationEffect.select && words.contains('into')) _deny();
    if ((step.effect == SqlOperationEffect.update || step.effect == SqlOperationEffect.delete) &&
        !words.contains('where')) {
      _deny();
    }
    if (words.where((w) => w == 'into').length > (step.effect == SqlOperationEffect.insert ? 1 : 0)) _deny();
    const functions = {
      'cast',
      'coalesce',
      'nullif',
      'abs',
      'round',
      'floor',
      'ceiling',
      'ceil',
      'lower',
      'upper',
      'trim',
      'ltrim',
      'rtrim',
      'substring',
      'substr',
      'length',
      'char_length',
      'count',
      'sum',
      'min',
      'max',
      'avg',
      'concat',
      'extract',
      'dateadd',
      'datediff',
    };
    for (final match in RegExp(r'([a-z_][a-z0-9_]*)\s*\(').allMatches(text)) {
      final name = match.group(1)!;
      if (functions.contains(name) && !text.substring(0, match.start).trimRight().endsWith('.')) continue;
      if ({'values', 'in', 'exists', 'as', 'where', 'and', 'or', 'not', 'when', 'then', 'else'}.contains(name)) {
        continue;
      }
      // Only the INSERT target may precede its column list; other calls are refused.
      final prefix = text.substring(0, match.start);
      if (step.effect == SqlOperationEffect.insert &&
          RegExp(r'^\s*insert\s+into\s+(?:[a-z_][a-z0-9_]*\s*\.\s*)?$').hasMatch(prefix)) {
        continue;
      }
      _deny();
    }
    final classified = SqlOperationClassifier().classifyPrepared(prepared).getOrThrow();
    if (classified.resources.any((r) => r.normalizedName.split('.').length > 2)) _deny();
    // Scalar key generation by MAX is never an operation output contract.
    if (step.outputs.isNotEmpty && RegExp(r'\bmax\s*\(').hasMatch(text)) _deny();
  }

  static Never _deny() => throw SqlOperationFailure(
    code: 'SQL_OPERATION_SQL_UNSUPPORTED',
    message: 'SQL is outside the supported transactional statement subset.',
  );
}
