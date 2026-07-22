import 'dart:ffi';

import 'package:ffi/ffi.dart';

int Function(Pointer<Utf16> source, Pointer<Utf16> destination, int size)? _cachedExpandEnvironmentStrings;

/// Expands `%VAR%` tokens the same way Windows resolves `REG_EXPAND_SZ`.
String expandWindowsEnvironmentStrings(
  String value, {
  String Function(String value)? expander,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || !trimmed.contains('%')) {
    return value;
  }

  return (expander ?? _expandWithWin32)(value);
}

String _expandWithWin32(String value) {
  final expand = _cachedExpandEnvironmentStrings ??= DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Uint32 Function(Pointer<Utf16> source, Pointer<Utf16> destination, Uint32 size),
        int Function(Pointer<Utf16> source, Pointer<Utf16> destination, int size)
      >('ExpandEnvironmentStringsW');

  final sourcePtr = value.toNativeUtf16();
  try {
    final requiredSize = expand(sourcePtr, nullptr, 0);
    if (requiredSize == 0) {
      return value;
    }

    final destinationPtr = calloc<Uint16>(requiredSize).cast<Utf16>();
    try {
      final written = expand(sourcePtr, destinationPtr, requiredSize);
      if (written == 0) {
        return value;
      }
      return destinationPtr.toDartString();
    } finally {
      calloc.free(destinationPtr);
    }
  } finally {
    calloc.free(sourcePtr);
  }
}
