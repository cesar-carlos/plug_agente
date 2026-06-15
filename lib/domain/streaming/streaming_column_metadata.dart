/// Column metadata derived from an encoded wire columnar payload.
List<Map<String, dynamic>>? buildStreamingColumnMetadataFromWireColumnar(
  Map<String, dynamic> columnar,
) {
  final columns = columnar['columns'];
  if (columns is! List<dynamic>) {
    return null;
  }
  final metadata = <Map<String, dynamic>>[];
  for (final column in columns) {
    if (column is! Map) {
      continue;
    }
    final name = column['name'];
    if (name is! String || name.isEmpty) {
      continue;
    }
    final type = column['type'];
    metadata.add(<String, dynamic>{
      'name': name,
      if (type is String) 'type': type,
    });
  }
  return metadata.isEmpty ? null : metadata;
}
