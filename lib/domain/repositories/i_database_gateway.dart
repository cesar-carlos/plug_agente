import 'package:result_dart/result_dart.dart';

import '../entities/query_request.dart';
import '../entities/query_response.dart';

abstract class IDatabaseGateway {
  Future<Result<bool>> testConnection(String connectionString);
  Future<Result<QueryResponse>> executeQuery(QueryRequest request);
  Future<Result<int>> executeNonQuery(String query, Map<String, dynamic>? parameters);
}
