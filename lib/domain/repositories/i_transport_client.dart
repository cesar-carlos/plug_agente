import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:result_dart/result_dart.dart';

abstract class ITransportClient {
  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? authToken,
  });
  Future<Result<void>> disconnect();
  Future<Result<void>> sendResponse(QueryResponse response);
  Stream<QueryRequest> get queryRequestStream;
  bool get isConnected;
  String get agentId;

  void setMessageCallback(
    void Function(String direction, String event, dynamic data)? callback,
  );
  void setOnTokenExpired(void Function()? callback);
  void setOnReconnectionNeeded(void Function()? callback);
}
