import 'package:result_dart/result_dart.dart';

abstract class ICompressor {
  Future<Result<List<Map<String, dynamic>>>> compress(
    List<Map<String, dynamic>> data,
  );

  Future<Result<List<Map<String, dynamic>>>> decompress(
    List<Map<String, dynamic>> data,
  );
}
