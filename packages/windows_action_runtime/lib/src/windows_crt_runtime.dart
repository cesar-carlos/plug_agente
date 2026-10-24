import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Binary CRT mode (`_O_BINARY`). Text mode must not translate pipes.
const int windowsCrtBinaryMode = 0x8000;

/// Do not let a later `CreateProcess` inherit this CRT descriptor.
const int windowsCrtNoInheritMode = 0x0080;

DynamicLibrary? _systemRuntime;

/// The OS-provided Universal CRT.
///
/// Uses the absolute system directory from Windows. Never searches CWD, PATH,
/// or a configured environment variable for this runtime DLL.
DynamicLibrary loadWindowsCrtRuntime() => _systemRuntime ??= _openSystemRuntime();

DynamicLibrary _openSystemRuntime() => using((arena) {
  const capacity = 32768;
  final path = arena<Uint16>(capacity);
  final directory = GetSystemDirectory(PWSTR(path.cast()), capacity);
  if (directory.value == 0 || directory.value >= capacity) {
    throw const ProcessException('', [], 'Unable to locate the Windows system runtime');
  }
  return DynamicLibrary.open('${path.cast<Utf16>().toDartString()}\\ucrtbase.dll');
});
