import 'dart:async';

import '../../domain/repositories/i_transport_client.dart';
import '../../application/use_cases/handle_query_request.dart';
import '../../core/logger/app_logger.dart';

class QueryProcessingService {
  final ITransportClient _transportClient;
  final HandleQueryRequest _handleQueryRequest;

  StreamSubscription? _subscription;

  QueryProcessingService(this._transportClient, this._handleQueryRequest);

  void start() {
    if (_subscription != null) {
      return;
    }

    AppLogger.info('Starting QueryProcessingService...');
    _subscription = _transportClient.queryRequestStream.listen(
      (request) async {
        AppLogger.info('Received Query Request: ${request.id}');

        final result = await _handleQueryRequest(request);

        result.fold(
          (_) => AppLogger.info('Query Request ${request.id} handled successfully'),
          (failure) => AppLogger.error('Failed to handle Query Request ${request.id}: $failure'),
        );
      },
      onError: (error) {
        AppLogger.error('Error in Query Request stream: $error');
      },
    );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    AppLogger.info('QueryProcessingService stopped');
  }
}
