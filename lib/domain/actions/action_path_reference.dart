import 'package:plug_agente/domain/actions/action_enums.dart';

class AgentActionPathReference {
  const AgentActionPathReference({
    required this.originalPath,
    this.canonicalPath,
    this.existsAtValidation,
    this.validatedAt,
    this.validationHash,
    this.pathChangePolicy,
  });

  final String originalPath;
  final String? canonicalPath;
  final bool? existsAtValidation;
  final DateTime? validatedAt;
  final String? validationHash;
  final AgentActionPathChangePolicy? pathChangePolicy;

  String get displayPath => canonicalPath ?? originalPath;

  AgentActionPathChangePolicy get effectivePathChangePolicy =>
      pathChangePolicy ?? AgentActionPathChangePolicy.failIfChanged;
}
