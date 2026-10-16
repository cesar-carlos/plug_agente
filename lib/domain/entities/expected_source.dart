import 'package:plug_agente/domain/entities/source_discovery.dart';
import 'package:plug_agente/domain/errors/failures.dart';

/// Enrolled durable identity, never inferred from a name or supplied SQL.
class ExpectedSource {
  const ExpectedSource({required this.dialect, required this.identityHash});
  factory ExpectedSource.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw.length != 3 ||
        raw['version'] != 1 ||
        !['postgres', 'mssql', 'sybase'].contains(raw['dialect']) ||
        raw['identityHash'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['identityHash'] as String)) {
      throw ValidationFailure('Invalid expected durable source identity.');
    }
    return ExpectedSource(dialect: raw['dialect'] as String, identityHash: raw['identityHash'] as String);
  }
  final String dialect;
  final String identityHash;
  Map<String, dynamic> toJson() => {'version': 1, 'dialect': dialect, 'identityHash': identityHash};
  void verify(SourceDiscovery actual) {
    if (actual.identityKind != (dialect == 'sybase' ? 'provisioned' : 'native') ||
        actual.dialect != dialect ||
        actual.identityHash != identityHash) {
      throw DatabaseFailure.withContext(
        code: 'SOURCE_IDENTITY_MISMATCH',
        message: 'Executing connection does not match enrolled durable source identity.',
        context: const {'retryable': false},
      );
    }
  }
}
