/// UTF-8 slice of captured stdout/stderr for paging (RPC or UI).
typedef CapturedOutputUtf8Window = ({
  String text,
  int nextOffset,
  int totalBytes,
  bool responseTruncated,
  int effectiveStart,
});
