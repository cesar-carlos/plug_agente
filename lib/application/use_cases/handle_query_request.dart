import 'package:plug_agente/application/services/compression_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/metrics/authorization_metrics.dart';
import 'package:result_dart/result_dart.dart';

class HandleQueryRequest {
  HandleQueryRequest(
    this._databaseGateway,
    this._transportClient,
    this._normalizerService,
    this._compressionService,
    this._authorizeSqlOperation,
    this._featureFlags, {
    AuthorizationMetricsCollector? authMetrics,
  }) : _authMetrics = authMetrics;
  final IDatabaseGateway _databaseGateway;
  final ITransportClient _transportClient;
  final QueryNormalizerService _normalizerService;
  final CompressionService _compressionService;
  final AuthorizeSqlOperation _authorizeSqlOperation;
  final FeatureFlags _featureFlags;
  final AuthorizationMetricsCollector? _authMetrics;

  QueryResponse _buildErrorResponse(
    QueryRequest request,
    String message,
  ) {
    return QueryResponse(
      id: request.id,
      requestId: request.id,
      agentId: request.agentId,
      data: const [],
      timestamp: DateTime.now(),
      error: message,
    );
  }

  Future<Result<void>> call(QueryRequest request) async {
    try {
      if (_featureFlags.enableClientTokenAuthorization &&
          (request.clientToken == null || request.clientToken!.isEmpty)) {
        final authFailure = domain.ConfigurationFailure.withContext(
          message: 'Client token is required for authorized SQL operations',
          context: {
            'authentication': true,
            'reason': 'missing_client_token',
            'user_message':
                'Client token obrigatorio. Gere um token e envie na requisicao.',
          },
        );
        final errorResponse = _buildErrorResponse(
          request,
          authFailure.context['user_message'] as String,
        );
        return _transportClient.sendResponse(errorResponse);
      }

      if (_featureFlags.enableClientTokenAuthorization &&
          request.clientToken != null &&
          request.clientToken!.isNotEmpty) {
        final authResult = await _authorizeSqlOperation(
          token: request.clientToken!,
          sql: request.query,
        );
        if (authResult.isError()) {
          final failure = authResult.exceptionOrNull()! as domain.Failure;
          final ctx = failure.context;
          _authMetrics?.recordDenied(
            clientId: ctx['client_id'] as String?,
            operation: ctx['operation'] as String?,
            resource: ctx['resource'] as String?,
            reason: ctx['reason'] as String?,
          );
          final errorMessage =
              failure is domain.ConfigurationFailure &&
                  failure.context.containsKey('user_message')
              ? failure.context['user_message'] as String
              : failure.message;
          final errorResponse = _buildErrorResponse(request, errorMessage);
          return _transportClient.sendResponse(errorResponse);
        }
        _authMetrics?.recordAuthorized();
      }

      final validation = SqlValidator.validateSqlForExecution(request.query);
      if (validation.isError()) {
        final failure = validation.exceptionOrNull()!;
        final errorMessage = failure is domain.Failure
            ? failure.message
            : failure.toString();
        final errorResponse = _buildErrorResponse(request, errorMessage);
        return _transportClient.sendResponse(errorResponse);
      }

      final queryResult = await _databaseGateway.executeQuery(request);

      return await queryResult.fold(
        (response) async {
          final normalizedResponse = await _normalizerService.normalize(
            response,
          );
          final compressionResult = await _compressionService.compress(
            normalizedResponse,
          );

          return await compressionResult.fold(
            (compressedResponse) async {
              return _transportClient.sendResponse(compressedResponse);
            },
            (failure) {
              return Failure(
                domain.QueryExecutionFailure.withContext(
                  message: 'Failed to compress response',
                  cause: failure,
                  context: {
                    'requestId': request.id,
                    'agentId': request.agentId,
                  },
                ),
              );
            },
          );
        },
        (failure) async {
          final errorMessage = failure is domain.Failure
              ? failure.message
              : failure.toString();
          final errorResponse = _buildErrorResponse(request, errorMessage);
          return _transportClient.sendResponse(errorResponse);
        },
      );
    } on Exception catch (error) {
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Failed to handle query request',
          cause: error,
          context: {
            'requestId': request.id,
            'agentId': request.agentId,
          },
        ),
      );
    }
  }
}
