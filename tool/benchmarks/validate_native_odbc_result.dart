import 'dart:convert';
import 'dart:io';

import 'package:odbc_fast/odbc_fast.dart';

import 'odbc_benchmark_fixture.dart';

// Keep dependency decoder failures outside the process that owns the fixture.
// This is also a minimal reproducer for the compressed buffer finalizer.
Future<void> main() async {
  final input = await stdin.transform(utf8.decoder).join();
  final messages = jsonDecode(input) as List<dynamic>;
  for (final message in messages) {
    final bytes = base64Decode(message as String);
    validateBenchmarkRows(BinaryProtocolParser.parse(bytes).rows);
  }
}
