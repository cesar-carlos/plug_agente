import 'dart:developer' as developer;

import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:result_dart/result_dart.dart';

class ClientTokenRepository implements IClientTokenRepository {
  ClientTokenRepository(this._localDataSource);

  final ClientTokenLocalDataSource _localDataSource;

  @override
  Future<ClientTokenSummary?> getTokenById(String tokenId) async {
    try {
      return await _localDataSource.getTokenById(tokenId);
    } on Exception catch (error, stackTrace) {
      // Log at error level so DB failures are distinguishable from "not found"
      // (null return). Callers that need to distinguish should use listTokens
      // or a Result-returning overload when the distinction matters.
      developer.log(
        'DB error loading client token by id — returning null',
        name: 'client_token_repository',
        error: error,
        stackTrace: stackTrace,
        level: 1000,
      );
      return null;
    }
  }

  @override
  Future<Result<String>> createToken(ClientTokenCreateRequest request) async {
    try {
      final token = await _localDataSource.createToken(request);
      return Success(token);
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to create local client token',
          cause: error,
          context: const {'operation': 'create_local_client_token'},
        ),
      );
    }
  }

  @override
  Future<Result<ClientTokenUpdateResult>> updateToken(
    String tokenId,
    ClientTokenCreateRequest request, {
    int? expectedVersion,
  }) async {
    try {
      final updateResult = await _localDataSource.updateToken(
        tokenId,
        request,
        expectedVersion: expectedVersion,
      );
      if (updateResult == null) {
        return Failure(
          domain.ValidationFailure(
            'Client token not found for update operation',
          ),
        );
      }
      return Success(updateResult);
    } on ClientTokenVersionConflictException catch (error) {
      final context = <String, dynamic>{
        'operation': 'update_local_client_token',
        'token_id': tokenId,
        'reason': 'token_version_conflict',
        'current_version': error.currentVersion,
      };
      if (expectedVersion != null) {
        context['expected_version'] = expectedVersion;
      }
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Client token was modified by another operation',
          context: context,
        ),
      );
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to update local client token',
          cause: error,
          context: {
            'operation': 'update_local_client_token',
            'token_id': tokenId,
          },
        ),
      );
    }
  }

  @override
  Future<Result<List<ClientTokenSummary>>> listTokens({
    ClientTokenListQuery? query,
  }) async {
    try {
      final tokens = await _localDataSource.listTokens(query: query);
      return Success(tokens);
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to list local client tokens',
          cause: error,
          context: const {'operation': 'list_local_client_tokens'},
        ),
      );
    }
  }

  @override
  Future<Result<void>> revokeToken(String tokenId) async {
    try {
      final didRevoke = await _localDataSource.markTokenRevoked(tokenId);
      if (!didRevoke) {
        return Failure(
          domain.ValidationFailure(
            'Client token not found for revoke operation',
          ),
        );
      }
      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to revoke local client token',
          cause: error,
          context: {
            'operation': 'revoke_local_client_token',
            'token_id': tokenId,
          },
        ),
      );
    }
  }

  @override
  Future<Result<void>> deleteToken(String tokenId) async {
    try {
      final didDelete = await _localDataSource.deleteToken(tokenId);
      if (!didDelete) {
        return Failure(
          domain.ValidationFailure(
            'Client token not found for delete operation',
          ),
        );
      }
      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to delete local client token',
          cause: error,
          context: {
            'operation': 'delete_local_client_token',
            'token_id': tokenId,
          },
        ),
      );
    }
  }
}
