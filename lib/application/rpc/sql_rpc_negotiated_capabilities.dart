Set<String> negotiatedPaginationModes(
  Map<String, dynamic> negotiatedExtensions,
) {
  final rawModes = negotiatedExtensions['paginationModes'];
  if (rawModes is! List<dynamic> || rawModes.isEmpty) {
    return {'page-offset', 'cursor-keyset', 'cursor-offset'};
  }
  return rawModes.whereType<String>().toSet();
}

bool supportsPageOffsetPagination(
  Map<String, dynamic> negotiatedExtensions,
) {
  final modes = negotiatedPaginationModes(negotiatedExtensions);
  return modes.contains('page-offset');
}

bool supportsCursorKeysetPagination(
  Map<String, dynamic> negotiatedExtensions,
) {
  final modes = negotiatedPaginationModes(negotiatedExtensions);
  return modes.contains('cursor-keyset') || modes.contains('cursor-offset');
}

bool supportsStreamingChunks(Map<String, dynamic> negotiatedExtensions) {
  final streamingResults = negotiatedExtensions['streamingResults'];
  if (streamingResults is bool) {
    return streamingResults;
  }
  return true;
}

/// Whether the transport handshake explicitly negotiated streaming result chunks.
bool isStreamingResultsNegotiated(Map<String, dynamic> negotiatedExtensions) {
  return negotiatedExtensions['streamingResults'] == true;
}
