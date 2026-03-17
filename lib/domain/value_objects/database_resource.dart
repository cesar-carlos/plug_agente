import 'package:flutter/foundation.dart';

enum DatabaseResourceType {
  table,
  view,
  unknown,
}

@immutable
class DatabaseResource {
  const DatabaseResource({
    required this.resourceType,
    required this.name,
  });

  factory DatabaseResource.fromJson(Map<String, dynamic> json) {
    final typeValue = (json['resource_type'] as String? ?? 'unknown')
        .toLowerCase();
    final resourceType = switch (typeValue) {
      'table' => DatabaseResourceType.table,
      'view' => DatabaseResourceType.view,
      _ => DatabaseResourceType.unknown,
    };

    final resourceName = json['resource'] as String? ?? '';
    return DatabaseResource(
      resourceType: resourceType,
      name: _normalizeName(resourceName),
    );
  }

  final DatabaseResourceType resourceType;
  final String name;

  String get normalizedName => _normalizeName(name);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DatabaseResource &&
        other.resourceType == resourceType &&
        other.normalizedName == normalizedName;
  }

  @override
  int get hashCode => Object.hash(resourceType, normalizedName);

  bool matches(String target) {
    final leftCandidates = _buildCandidates(normalizedName);
    final rightCandidates = _buildCandidates(_normalizeName(target));
    return leftCandidates.any(rightCandidates.contains);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'resource_type': resourceType.name,
      'resource': normalizedName,
    };
  }

  static String _normalizeName(String value) {
    final trimmed = value.trim().toLowerCase();
    return trimmed
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '')
        .replaceAll('`', '')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'\.+'), '.');
  }

  static String _baseName(String normalized) {
    final parts = normalized.split('.');
    return parts.isEmpty ? normalized : parts.last;
  }

  static Set<String> _buildCandidates(String normalized) {
    final base = _baseName(normalized);
    return <String>{normalized, base};
  }
}
