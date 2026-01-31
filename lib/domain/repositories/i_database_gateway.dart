import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:result_dart/result_dart.dart';

abstract class IDatabaseGateway {
  Future<Result<bool>> testConnection(String connectionString);
  Future<Result<QueryResponse>> executeQuery(QueryRequest request);
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters,
  );
}
