import 'package:result_dart/result_dart.dart';

import '../entities/query_request.dart';
import '../entities/query_response.dart';

abstract class ITransportClient {
  Future<Result<void>> connect(String serverUrl, String agentId, {String? authToken});
  Future<Result<void>> disconnect();
  Future<Result<void>> sendResponse(QueryResponse response);
  Stream<QueryRequest> get queryRequestStream;
  bool get isConnected;
  String get agentId;

  void setMessageCallback(Function(String direction, String event, dynamic data)? callback);
  void setOnTokenExpired(Function()? callback);
  void setOnReconnectionNeeded(Function()? callback);
}
