import 'package:checks/checks.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/ports/i_hub_access_token_renewer.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/agent_hub_profile_rest_client.dart';
import 'package:result_dart/result_dart.dart';
import 'package:test/test.dart';

class _MockDio extends Mock implements Dio {}

class _MockRenewer extends Mock implements IHubAccessTokenRenewer {}

void main() {
  late _MockDio dio;
  late AgentHubProfileRestClient client;

  setUpAll(() {
    registerFallbackValue(Options());
    registerFallbackValue(RequestOptions(path: '/'));
  });

  setUp(() {
    dio = _MockDio();
    client = AgentHubProfileRestClient(dio);
  });

  test('should parse 200 response with agent.profileVersion', () async {
    when(
      () => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/v1/agents/x/profile'),
        statusCode: 200,
        data: <String, dynamic>{
          'agent': <String, dynamic>{
            'profileVersion': 4,
            'profileUpdatedAt': '2026-01-01T00:00:00.000Z',
          },
        },
      ),
    );

    final result = await client.patchProfile(
      serverUrl: 'https://hub.example',
      agentId: '3183a9f2-429b-46d6-a339-3580e5e5cb31',
      accessToken: 'jwt',
      body: <String, dynamic>{'name': 'A'},
    );

    check(result.isSuccess()).isTrue();
    final value = result.getOrNull();
    check(value).isNotNull();
    check(value!.profileVersion).equals(4);
    check(value.profileUpdatedAt).equals('2026-01-01T00:00:00.000Z');
  });

  test('should map 401 to Failure', () async {
    when(
      () => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 401,
          data: <String, dynamic>{'message': 'Unauthorized'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    final result = await client.patchProfile(
      serverUrl: 'https://hub.example',
      agentId: '3183a9f2-429b-46d6-a339-3580e5e5cb31',
      accessToken: 'jwt',
      body: <String, dynamic>{'name': 'A'},
    );

    check(result.isError()).isTrue();
    expect(
      result.exceptionOrNull().toString(),
      contains('Unauthorized'),
    );
  });

  test('should refresh access token and retry PATCH once on 401', () async {
    final renewer = _MockRenewer();
    final retryClient = AgentHubProfileRestClient(dio, accessTokenRenewer: renewer);
    var patchCalls = 0;

    when(
      () => renewer.renew(
        serverUrl: any(named: 'serverUrl'),
        accessToken: any(named: 'accessToken'),
        configId: any(named: 'configId'),
      ),
    ).thenAnswer(
      (_) async => const Success(
        AuthToken(token: 'fresh-jwt', refreshToken: 'refresh-2'),
      ),
    );

    when(
      () => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((invocation) async {
      patchCalls++;
      final options = invocation.namedArguments[#options] as Options;
      final authorization = options.headers?['Authorization'] as String?;
      if (authorization == 'Bearer jwt') {
        throw DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 401,
            data: <String, dynamic>{'message': 'jwt expired'},
          ),
          type: DioExceptionType.badResponse,
        );
      }

      return Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/v1/agents/x/profile'),
        statusCode: 200,
        data: <String, dynamic>{
          'agent': <String, dynamic>{'profileVersion': 2},
        },
      );
    });

    final result = await retryClient.patchProfile(
      serverUrl: 'https://hub.example',
      agentId: '3183a9f2-429b-46d6-a339-3580e5e5cb31',
      accessToken: 'jwt',
      body: <String, dynamic>{'name': 'A'},
    );

    check(result.isSuccess()).isTrue();
    check(result.getOrNull()?.profileVersion).equals(2);
    check(patchCalls).equals(2);
    verify(
      () => renewer.renew(
        serverUrl: 'https://hub.example',
        accessToken: 'jwt',
      ),
    ).called(1);
  });

  test('should pass configId to token renewer on GET 401 retry', () async {
    final renewer = _MockRenewer();
    final retryClient = AgentHubProfileRestClient(dio, accessTokenRenewer: renewer);

    when(
      () => renewer.renew(
        serverUrl: any(named: 'serverUrl'),
        accessToken: any(named: 'accessToken'),
        configId: any(named: 'configId'),
      ),
    ).thenAnswer(
      (_) async => const Success(
        AuthToken(token: 'fresh-jwt', refreshToken: 'refresh-2'),
      ),
    );

    when(
      () => dio.get<dynamic>(
        any(),
        options: any(named: 'options'),
      ),
    ).thenAnswer((invocation) async {
      final options = invocation.namedArguments[#options] as Options;
      final authorization = options.headers?['Authorization'] as String?;
      if (authorization == 'Bearer jwt') {
        return Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 401,
          data: <String, dynamic>{'message': 'jwt expired'},
        );
      }
      return Response(
        requestOptions: RequestOptions(path: '/api/v1/agents/agent-1/profile'),
        statusCode: 200,
        data: <String, dynamic>{
          'agent': <String, dynamic>{'profileVersion': 1},
        },
      );
    });

    final result = await retryClient.fetchProfileCatalog(
      serverUrl: 'https://hub.example',
      agentId: 'agent-1',
      accessToken: 'jwt',
      configId: 'cfg-profile',
    );

    check(result.isSuccess()).isTrue();
    verify(
      () => renewer.renew(
        serverUrl: 'https://hub.example',
        accessToken: 'jwt',
        configId: 'cfg-profile',
      ),
    ).called(1);
  });

  test('should parse profileVersion when JSON numeric is double', () async {
    when(
      () => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/v1/agents/x/profile'),
        statusCode: 200,
        data: <String, dynamic>{
          'agent': <String, dynamic>{
            'profileVersion': 9.0,
          },
        },
      ),
    );

    final result = await client.patchProfile(
      serverUrl: 'https://hub.example',
      agentId: '3183a9f2-429b-46d6-a339-3580e5e5cb31',
      accessToken: 'jwt',
      body: <String, dynamic>{'name': 'A'},
    );

    check(result.getOrNull()?.profileVersion).equals(9);
  });

  test('should map 403 to Failure', () async {
    when(
      () => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 403,
          data: <String, dynamic>{'message': 'Forbidden agent'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    final result = await client.patchProfile(
      serverUrl: 'https://hub.example',
      agentId: '3183a9f2-429b-46d6-a339-3580e5e5cb31',
      accessToken: 'jwt',
      body: <String, dynamic>{'name': 'A'},
    );

    check(result.isError()).isTrue();
    expect(result.exceptionOrNull().toString(), contains('Forbidden agent'));
  });

  test('should map 409 to Failure', () async {
    when(
      () => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 409,
          data: <String, dynamic>{'message': 'Version conflict'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    final result = await client.patchProfile(
      serverUrl: 'https://hub.example',
      agentId: '3183a9f2-429b-46d6-a339-3580e5e5cb31',
      accessToken: 'jwt',
      body: <String, dynamic>{'name': 'A'},
    );

    check(result.isError()).isTrue();
    expect(result.exceptionOrNull(), isA<domain.ProfileVersionConflictFailure>());
    expect(result.exceptionOrNull().toString(), contains('Version conflict'));
  });

  test('should parse 200 when nested agent map is not Map<String, dynamic>', () async {
    when(
      () => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/v1/agents/x/profile'),
        statusCode: 200,
        data: <String, dynamic>{
          'agent': Map<Object?, Object?>.from(<Object?, Object?>{
            'profileVersion': 12,
            'profileUpdatedAt': '2026-05-29T20:14:50.000Z',
          }),
        },
      ),
    );

    final result = await client.patchProfile(
      serverUrl: 'https://hub.example',
      agentId: '3183a9f2-429b-46d6-a339-3580e5e5cb31',
      accessToken: 'jwt',
      body: <String, dynamic>{'name': 'A'},
    );

    check(result.isSuccess()).isTrue();
    check(result.getOrNull()?.profileVersion).equals(12);
    check(result.getOrNull()?.profileUpdatedAt).equals('2026-05-29T20:14:50.000Z');
  });

  test('should accept profile_version and profile_updated_at snake_case fields', () async {
    when(
      () => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/v1/agents/x/profile'),
        statusCode: 200,
        data: <String, dynamic>{
          'agent': <String, dynamic>{
            'profile_version': 3,
            'profile_updated_at': '2026-04-08T10:20:00.000Z',
          },
        },
      ),
    );

    final result = await client.patchProfile(
      serverUrl: 'https://hub.example',
      agentId: '3183a9f2-429b-46d6-a339-3580e5e5cb31',
      accessToken: 'jwt',
      body: <String, dynamic>{'name': 'A'},
    );

    check(result.getOrNull()?.profileVersion).equals(3);
    check(result.getOrNull()?.profileUpdatedAt).equals('2026-04-08T10:20:00.000Z');
  });

  test('should strip /agents from serverUrl when building PATCH URL', () async {
    when(
      () => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/v1/agents/x/profile'),
        statusCode: 200,
        data: <String, dynamic>{
          'agent': <String, dynamic>{'profileVersion': 1},
        },
      ),
    );

    await client.patchProfile(
      serverUrl: 'https://hub.example/agents',
      agentId: '3183a9f2-429b-46d6-a339-3580e5e5cb31',
      accessToken: 'jwt',
      body: <String, dynamic>{'name': 'A'},
    );

    final capturedUrl =
        verify(
              () => dio.patch<dynamic>(
                captureAny(),
                data: any(named: 'data'),
                options: any(named: 'options'),
              ),
            ).captured.first
            as String;

    check(capturedUrl).equals(
      'https://hub.example/api/v1/agents/3183a9f2-429b-46d6-a339-3580e5e5cb31/profile',
    );
  });

  test('should pass Idempotency-Key header when idempotencyKey is provided', () async {
    when(
      () => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/api/v1/agents/x/profile'),
        statusCode: 200,
        data: <String, dynamic>{
          'agent': <String, dynamic>{'profileVersion': 1},
        },
      ),
    );

    await client.patchProfile(
      serverUrl: 'https://hub.example',
      agentId: '3183a9f2-429b-46d6-a339-3580e5e5cb31',
      accessToken: 'jwt',
      body: <String, dynamic>{'name': 'A'},
      idempotencyKey: 'test-idem-key',
    );

    final captured =
        verify(
              () => dio.patch<dynamic>(
                any(),
                data: any(named: 'data'),
                options: captureAny(named: 'options'),
              ),
            ).captured.single
            as Options;

    check(captured.headers?['Idempotency-Key']).equals('test-idem-key');
  });

  group('validation', () {
    test('should reject empty serverUrl', () async {
      final result = await client.patchProfile(
        serverUrl: '  ',
        agentId: 'agent-1',
        accessToken: 'jwt',
        body: <String, dynamic>{'name': 'A'},
      );

      check(result.isError()).isTrue();
      expect(result.exceptionOrNull(), isA<domain.ValidationFailure>());
      verifyNever(
        () => dio.patch<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      );
    });

    test('should reject empty agentId', () async {
      final result = await client.patchProfile(
        serverUrl: 'https://hub.example',
        agentId: '',
        accessToken: 'jwt',
        body: <String, dynamic>{'name': 'A'},
      );

      check(result.isError()).isTrue();
      expect(result.exceptionOrNull(), isA<domain.ValidationFailure>());
    });

    test('should reject empty accessToken', () async {
      final result = await client.patchProfile(
        serverUrl: 'https://hub.example',
        agentId: 'agent-1',
        accessToken: ' ',
        body: <String, dynamic>{'name': 'A'},
      );

      check(result.isError()).isTrue();
      expect(result.exceptionOrNull(), isA<domain.ValidationFailure>());
    });
  });

  group('error responses', () {
    test('should map network errors without HTTP status to NetworkFailure', () async {
      when(
        () => dio.patch<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      final result = await client.patchProfile(
        serverUrl: 'https://hub.example',
        agentId: 'agent-1',
        accessToken: 'jwt',
        body: <String, dynamic>{'name': 'A'},
      );

      check(result.isError()).isTrue();
      expect(result.exceptionOrNull(), isA<domain.NetworkFailure>());
    });

    test('should map 429 to Failure with body message', () async {
      when(
        () => dio.patch<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 429,
            data: <String, dynamic>{'message': 'Rate limited'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await client.patchProfile(
        serverUrl: 'https://hub.example',
        agentId: 'agent-1',
        accessToken: 'jwt',
        body: <String, dynamic>{'name': 'A'},
      );

      check(result.isError()).isTrue();
      expect(result.exceptionOrNull().toString(), contains('Rate limited'));
    });

    test('should use default message for unknown HTTP status', () async {
      when(
        () => dio.patch<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 500,
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await client.patchProfile(
        serverUrl: 'https://hub.example',
        agentId: 'agent-1',
        accessToken: 'jwt',
        body: <String, dynamic>{'name': 'A'},
      );

      check(result.isError()).isTrue();
      expect(result.exceptionOrNull().toString(), contains('HTTP 500'));
    });

    test('should parse error message when body map is not Map<String, dynamic>', () async {
      when(
        () => dio.patch<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          response: Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: 403,
            data: Map<Object?, Object?>.from(<Object?, Object?>{'message': 'Denied'}),
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await client.patchProfile(
        serverUrl: 'https://hub.example',
        agentId: 'agent-1',
        accessToken: 'jwt',
        body: <String, dynamic>{'name': 'A'},
      );

      expect(result.exceptionOrNull().toString(), contains('Denied'));
    });
  });

  group('200 response parsing', () {
    test('should fail when response body is null', () async {
      when(
        () => dio.patch<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 200,
        ),
      );

      final result = await client.patchProfile(
        serverUrl: 'https://hub.example',
        agentId: 'agent-1',
        accessToken: 'jwt',
        body: <String, dynamic>{'name': 'A'},
      );

      check(result.isError()).isTrue();
      expect(result.exceptionOrNull(), isA<domain.ServerFailure>());
      expect(result.exceptionOrNull().toString(), contains('empty profile response'));
    });

    test('should fail when agent object is missing', () async {
      when(
        () => dio.patch<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 200,
          data: <String, dynamic>{'status': 'ok'},
        ),
      );

      final result = await client.patchProfile(
        serverUrl: 'https://hub.example',
        agentId: 'agent-1',
        accessToken: 'jwt',
        body: <String, dynamic>{'name': 'A'},
      );

      expect(result.exceptionOrNull().toString(), contains('missing agent object'));
    });

    test('should fail when profileVersion is invalid', () async {
      when(
        () => dio.patch<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 200,
          data: <String, dynamic>{
            'agent': <String, dynamic>{'profileVersion': 'not-a-number'},
          },
        ),
      );

      final result = await client.patchProfile(
        serverUrl: 'https://hub.example',
        agentId: 'agent-1',
        accessToken: 'jwt',
        body: <String, dynamic>{'name': 'A'},
      );

      expect(result.exceptionOrNull().toString(), contains('invalid profileVersion'));
    });

    test('should parse profileVersion when encoded as string', () async {
      when(
        () => dio.patch<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 200,
          data: <String, dynamic>{
            'agent': <String, dynamic>{'profileVersion': '15'},
          },
        ),
      );

      final result = await client.patchProfile(
        serverUrl: 'https://hub.example',
        agentId: 'agent-1',
        accessToken: 'jwt',
        body: <String, dynamic>{'name': 'A'},
      );

      check(result.getOrNull()?.profileVersion).equals(15);
    });

    test('should parse 200 when top-level data map is not Map<String, dynamic>', () async {
      when(
        () => dio.patch<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 200,
          data: Map<Object?, Object?>.from(<Object?, Object?>{
            'agent': <String, dynamic>{'profileVersion': 20},
          }),
        ),
      );

      final result = await client.patchProfile(
        serverUrl: 'https://hub.example',
        agentId: 'agent-1',
        accessToken: 'jwt',
        body: <String, dynamic>{'name': 'A'},
      );

      check(result.getOrNull()?.profileVersion).equals(20);
    });
  });

  test('should convert wss serverUrl to https when building PATCH URL', () async {
    when(
      () => dio.patch<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/'),
        statusCode: 200,
        data: <String, dynamic>{
          'agent': <String, dynamic>{'profileVersion': 1},
        },
      ),
    );

    await client.patchProfile(
      serverUrl: 'wss://hub.example/agents',
      agentId: 'agent-1',
      accessToken: 'jwt',
      body: <String, dynamic>{'name': 'A'},
    );

    final capturedUrl =
        verify(
              () => dio.patch<dynamic>(
                captureAny(),
                data: any(named: 'data'),
                options: any(named: 'options'),
              ),
            ).captured.first
            as String;

    check(capturedUrl).equals('https://hub.example/api/v1/agents/agent-1/profile');
  });

  test('should fetch profile catalog on GET 200', () async {
    when(
      () => dio.get<dynamic>(
        any(),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/api/v1/agents/agent-1/profile'),
        statusCode: 200,
        headers: Headers.fromMap(<String, List<String>>{
          'x-request-id': <String>['req-fetch-1'],
        }),
        data: <String, dynamic>{
          'agent': <String, dynamic>{
            'profileVersion': 6,
            'name': 'ACME',
            'tradeName': 'ACME',
            'document': '59261947000107',
            'documentType': 'cnpj',
            'mobile': '65992865050',
            'email': 'a@b.com',
            'address': <String, dynamic>{
              'street': 'Av Brasil',
              'number': '130',
              'district': 'Centro',
              'postalCode': '78300096',
              'city': 'City',
              'state': 'MT',
            },
          },
        },
      ),
    );

    final result = await client.fetchProfileCatalog(
      serverUrl: 'https://hub.example',
      agentId: 'agent-1',
      accessToken: 'jwt',
    );

    check(result.isSuccess()).isTrue();
    check(result.getOrNull()?.profileVersion).equals(6);
    check(result.getOrNull()?.agentPayload['name']).equals('ACME');
  });
}
