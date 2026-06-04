import 'package:checks/checks.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/ports/i_hub_access_token_renewer.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/hub_http_auth_retry.dart';
import 'package:result_dart/result_dart.dart';
import 'package:test/test.dart';

class _MockRenewer extends Mock implements IHubAccessTokenRenewer {}

void main() {
  late _MockRenewer renewer;

  setUp(() {
    renewer = _MockRenewer();
  });

  test('should retry request once after renewing access token on 401', () async {
    var attempts = 0;
    when(
      () => renewer.renew(
        serverUrl: any(named: 'serverUrl'),
        accessToken: any(named: 'accessToken'),
        configId: any(named: 'configId'),
      ),
    ).thenAnswer(
      (_) async => const Success(
        AuthToken(token: 'fresh-access', refreshToken: 'refresh-2'),
      ),
    );

    final result = await HubHttpAuthRetry.execute<String>(
      serverUrl: 'https://hub.example',
      accessToken: 'expired-access',
      accessTokenRenewer: renewer,
      request: (token) async {
        attempts++;
        if (token == 'expired-access') {
          return Failure(
            domain.ServerFailure.withContext(
              message: 'jwt expired',
              context: const {'statusCode': AppConstants.httpStatusUnauthorized},
            ),
          );
        }
        return const Success('ok');
      },
    );

    check(result.isSuccess()).isTrue();
    check(result.getOrNull()).equals('ok');
    check(attempts).equals(2);
    verify(
      () => renewer.renew(
        serverUrl: 'https://hub.example',
        accessToken: 'expired-access',
      ),
    ).called(1);
  });

  test('should return renew failure when token renewal fails', () async {
    when(
      () => renewer.renew(
        serverUrl: any(named: 'serverUrl'),
        accessToken: any(named: 'accessToken'),
        configId: any(named: 'configId'),
      ),
    ).thenAnswer(
      (_) async => Failure(
        domain.ConfigurationFailure('No refresh token available'),
      ),
    );

    final result = await HubHttpAuthRetry.execute<String>(
      serverUrl: 'https://hub.example',
      accessToken: 'expired-access',
      accessTokenRenewer: renewer,
      request: (_) async => Failure(
        domain.ServerFailure.withContext(
          message: 'unauthorized',
          context: const {'statusCode': AppConstants.httpStatusUnauthorized},
        ),
      ),
    );

    check(result.isError()).isTrue();
    check(result.exceptionOrNull()).isA<domain.ConfigurationFailure>();
    verify(
      () => renewer.renew(
        serverUrl: 'https://hub.example',
        accessToken: 'expired-access',
      ),
    ).called(1);
  });

  test('should not renew on non-401 failures', () async {
    final result = await HubHttpAuthRetry.execute<String>(
      serverUrl: 'https://hub.example',
      accessToken: 'access',
      accessTokenRenewer: renewer,
      request: (_) async => Failure(
        domain.ServerFailure.withContext(
          message: 'server error',
          context: const {'statusCode': 500},
        ),
      ),
    );

    check(result.isError()).isTrue();
    verifyNever(
      () => renewer.renew(
        serverUrl: any(named: 'serverUrl'),
        accessToken: any(named: 'accessToken'),
        configId: any(named: 'configId'),
      ),
    );
  });

  test('should skip renewal when renewer is null', () async {
    final result = await HubHttpAuthRetry.execute<String>(
      serverUrl: 'https://hub.example',
      accessToken: 'expired-access',
      request: (_) async => Failure(
        domain.ServerFailure.withContext(
          message: 'jwt expired',
          context: const {'statusCode': AppConstants.httpStatusUnauthorized},
        ),
      ),
    );

    check(result.isError()).isTrue();
    verifyNever(
      () => renewer.renew(
        serverUrl: any(named: 'serverUrl'),
        accessToken: any(named: 'accessToken'),
        configId: any(named: 'configId'),
      ),
    );
  });

  test('should not renew when first attempt succeeds', () async {
    final result = await HubHttpAuthRetry.execute<String>(
      serverUrl: 'https://hub.example',
      accessToken: 'valid-access',
      accessTokenRenewer: renewer,
      request: (_) async => const Success('ok'),
    );

    check(result.isSuccess()).isTrue();
    verifyNever(
      () => renewer.renew(
        serverUrl: any(named: 'serverUrl'),
        accessToken: any(named: 'accessToken'),
        configId: any(named: 'configId'),
      ),
    );
  });
}
