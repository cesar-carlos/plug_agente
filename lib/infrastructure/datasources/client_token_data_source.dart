import 'package:dio/dio.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class ClientTokenDataSource {
  ClientTokenDataSource(this._dio);

  static const String _basePath = '/client-tokens';

  final Dio _dio;

  Future<Result<String>> createToken(
    String serverUrl,
    ClientTokenCreateRequest request,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$serverUrl$_basePath',
        data: request.toJson(),
      );
      final data = response.data ?? const <String, dynamic>{};
      final token = data['token'] as String?;
      if (token == null || token.isEmpty) {
        return Failure(
          domain.ServerFailure(
            'Token creation response does not include token',
          ),
        );
      }
      return Success(token);
    } on DioException catch (error) {
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Failed to create client token',
          cause: error,
          context: {
            'operation': 'create_client_token',
          },
        ),
      );
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Unexpected error while creating client token',
          cause: error,
          context: {
            'operation': 'create_client_token',
          },
        ),
      );
    }
  }

  Future<Result<List<ClientTokenSummary>>> listTokens(String serverUrl) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$serverUrl$_basePath',
      );
      final data = response.data ?? const <String, dynamic>{};
      final rawItems = data['items'] as List<dynamic>? ?? const <dynamic>[];
      final tokens = rawItems
          .whereType<Map<String, dynamic>>()
          .map(ClientTokenSummary.fromJson)
          .toList();
      return Success(tokens);
    } on DioException catch (error) {
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Failed to list client tokens',
          cause: error,
          context: {
            'operation': 'list_client_tokens',
          },
        ),
      );
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Unexpected error while listing client tokens',
          cause: error,
          context: {
            'operation': 'list_client_tokens',
          },
        ),
      );
    }
  }

  Future<Result<void>> revokeToken(String serverUrl, String tokenId) async {
    try {
      await _dio.post<void>(
        '$serverUrl$_basePath/$tokenId/revoke',
      );
      return const Success(unit);
    } on DioException catch (error) {
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Failed to revoke client token',
          cause: error,
          context: {
            'operation': 'revoke_client_token',
            'token_id': tokenId,
          },
        ),
      );
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Unexpected error while revoking client token',
          cause: error,
          context: {
            'operation': 'revoke_client_token',
            'token_id': tokenId,
          },
        ),
      );
    }
  }
}
