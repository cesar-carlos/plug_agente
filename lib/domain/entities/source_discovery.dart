import 'package:plug_agente/domain/entities/config.dart';
import 'package:result_dart/result_dart.dart';

class SourceDiscovery {
  const SourceDiscovery({
    required this.database,
    required this.dialect,
    required this.identityHash,
    required this.identityKind,
    required this.engineVersion,
  });
  final String database;
  final String dialect;
  final String identityHash;
  final String identityKind;
  final String engineVersion;
  Map<String, dynamic> toJson() => {
    'contractVersion': 1,
    'database': database,
    'dialect': dialect,
    'identityHash': identityHash,
    'identityKind': identityKind,
    'engineVersion': engineVersion,
    'verifiedAt': DateTime.now().toUtc().toIso8601String(),
  };
}

abstract interface class ISourceDiscoveryProbe {
  Future<Result<SourceDiscovery>> inspect(Config config, String database);
}
