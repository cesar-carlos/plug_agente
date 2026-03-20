/// Helpers for expanding ODBC max result buffer after driver "buffer too small" errors.
///
/// Extracted from `OdbcDatabaseGateway` for unit testing and readability.
class OdbcGatewayBufferExpansion {
  OdbcGatewayBufferExpansion._();

  static const int bufferRetryMarginBytes = 1024 * 1024;
  static const int maxAutoExpandedBufferBytes = 256 * 1024 * 1024;

  static final RegExp _needBytesPattern = RegExp(
    r'need\s+(\d+)\s+bytes',
    caseSensitive: false,
  );

  /// Parses "need N bytes" style messages from some ODBC drivers.
  static int? extractRequiredBufferBytes(String message) {
    final match = _needBytesPattern.firstMatch(message);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1) ?? '');
  }

  /// Computes a larger `maxResultBufferBytes` for retry after a buffer error.
  static int calculateExpandedBufferBytes({
    required int currentBufferBytes,
    required String errorMessage,
  }) {
    final requiredBufferBytes = extractRequiredBufferBytes(errorMessage);

    if (requiredBufferBytes == null) {
      final doubledBuffer = currentBufferBytes * 2;
      if (doubledBuffer > maxAutoExpandedBufferBytes) {
        return maxAutoExpandedBufferBytes;
      }
      return doubledBuffer;
    }

    final withMargin = requiredBufferBytes + bufferRetryMarginBytes;
    if (withMargin > maxAutoExpandedBufferBytes) {
      return maxAutoExpandedBufferBytes;
    }
    if (withMargin < currentBufferBytes) {
      return currentBufferBytes;
    }
    return withMargin;
  }

  static bool messageIndicatesBufferTooSmall(String errorMessage) {
    return errorMessage.toLowerCase().contains('buffer too small');
  }
}
