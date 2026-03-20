/// Outbound Socket.IO PayloadFrame compression strategy (agent -> hub).
///
/// Wire values remain only `cmp: gzip` or `cmp: none`. [auto] decides per payload.
enum OutboundCompressionMode {
  /// Never compress outbound frames.
  none,

  /// Compress with GZIP when size is at least the negotiated threshold (legacy behavior).
  gzip,

  /// Like [gzip], but skip compression when the GZIP output is not smaller than raw bytes.
  auto;

  String get storageName => name;
}
