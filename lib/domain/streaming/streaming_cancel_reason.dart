/// Why an in-flight ODBC streaming execution was cancelled.
enum StreamingCancelReason {
  /// User cancelled or left the flow.
  user,

  /// Playground UI hit the configured max in-memory row cap (successful stop).
  playgroundRowCap,

  /// Backpressure buffer overflowed; hub not consuming fast enough.
  backpressureOverflow,

  /// Socket disconnected; stream cancelled to release ODBC resources.
  socketDisconnect,
}
