import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_hub_access_token_renewer.dart';
import 'package:result_dart/result_dart.dart';

/// Retries a hub HTTP request once after renewing the access token on 401.
abstract final class HubHttpAuthRetry {
  static Future<Result<T>> execute<T extends Object>({
    required Future<Result<T>> Function(String accessToken) request,
    required String serverUrl,
    required String accessToken,
    String? configId,
    IHubAccessTokenRenewer? accessTokenRenewer,
  }) async {
    final firstAttempt = await request(accessToken.trim());
    if (firstAttempt.isSuccess() || accessTokenRenewer == null) {
      return firstAttempt;
    }

    final failure = firstAttempt.exceptionOrNull();
    if (!_isUnauthorizedFailure(failure)) {
      return firstAttempt;
    }

    final renewResult = await accessTokenRenewer.renew(
      serverUrl: serverUrl,
      accessToken: accessToken,
      configId: configId,
    );
    if (renewResult.isError()) {
      return Failure(renewResult.exceptionOrNull()!);
    }

    return request(renewResult.getOrThrow().token.trim());
  }

  static bool _isUnauthorizedFailure(Object? failure) {
    if (failure is! domain.Failure) {
      return false;
    }
    final statusCode = failure.context['statusCode'];
    if (statusCode == AppConstants.httpStatusUnauthorized) {
      return true;
    }
    final message = failure.message.toLowerCase();
    return message.contains('jwt expired') || message.contains('session expired') || message.contains('unauthorized');
  }
}
