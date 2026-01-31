import 'dart:async';

import 'package:plug_agente/application/use_cases/handle_query_request.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';

class QueryProcessingService {
  QueryProcessingService(this._transportClient, this._handleQueryRequest);
  final ITransportClient _transportClient;
  final HandleQueryRequest _handleQueryRequest;

  StreamSubscription<dynamic>? _subscription;

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
          (_) => AppLogger.info(
            'Query Request ${request.id} handled successfully',
          ),
          (failure) => AppLogger.error(
            'Failed to handle Query Request ${request.id}: $failure',
          ),
        );
      },
      onError: (Object error) {
        AppLogger.error('Error in Query Request stream: $error');
      },
    );
  }

  void stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    AppLogger.info('QueryProcessingService stopped');
  }
}
