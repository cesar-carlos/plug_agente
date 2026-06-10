/// Returns the lowercase file extension including the leading dot, or null.
String? extensionOf(String? path) {
  if (path == null) {
    return null;
  }

  final lastSeparator = path.lastIndexOf(RegExp(r'[\\/]'));
  final fileName = lastSeparator >= 0 ? path.substring(lastSeparator + 1) : path;
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == fileName.length - 1) {
    return null;
  }

  return fileName.substring(dotIndex).toLowerCase();
}
