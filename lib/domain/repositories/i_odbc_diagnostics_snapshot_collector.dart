import 'package:result_dart/result_dart.dart';

abstract class IOdbcDiagnosticsSnapshotCollector {
  Future<Result<Map<String, dynamic>>> collectSnapshot();
}
