enum DatabaseResourceType {
  table,
  view,
  unknown,
}

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

  bool matches(String target) {
    return normalizedName == _normalizeName(target);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'resource_type': resourceType.name,
      'resource': normalizedName,
    };
  }

  static String _normalizeName(String value) {
    final trimmed = value.trim().toLowerCase();
    return trimmed.replaceAll('[', '').replaceAll(']', '');
  }
}
