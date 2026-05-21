import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';

/// Redacted file metadata attached to execution preflight diagnostics.
abstract final class ActionPathPreflightMetadata {
  static Map<String, Object?> forValidatedPath(AgentActionValidatedPath path) {
    return <String, Object?>{
      'canonical_path': path.canonicalPath,
      if (path.sizeBytes != null) 'size_bytes': path.sizeBytes,
      if (path.lastModifiedUtc != null) 'last_modified_utc': path.lastModifiedUtc!.toIso8601String(),
      if (path.contentHash != null) 'content_hash_prefix': _hashPrefix(path.contentHash!),
    };
  }

  static String _hashPrefix(String hash) {
    const prefixLength = 12;
    if (hash.length <= prefixLength) {
      return hash;
    }

    return '${hash.substring(0, prefixLength)}…';
  }
}
