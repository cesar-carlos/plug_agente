import 'package:checks/checks.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/infrastructure/external_services/agent_hub_profile_rest_client.dart';
import 'package:test/test.dart';

class _MockDio extends Mock implements Dio {}

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
      () => dio.patch<Map<String, dynamic>>(
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
      () => dio.patch<Map<String, dynamic>>(
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

  test('should parse profileVersion when JSON numeric is double', () async {
    when(
      () => dio.patch<Map<String, dynamic>>(
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
      () => dio.patch<Map<String, dynamic>>(
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
      () => dio.patch<Map<String, dynamic>>(
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
    expect(result.exceptionOrNull().toString(), contains('Version conflict'));
  });

  test('should pass Idempotency-Key header when idempotencyKey is provided', () async {
    when(
      () => dio.patch<Map<String, dynamic>>(
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
              () => dio.patch<Map<String, dynamic>>(
                any(),
                data: any(named: 'data'),
                options: captureAny(named: 'options'),
              ),
            ).captured.single
            as Options;

    check(captured.headers?['Idempotency-Key']).equals('test-idem-key');
  });
}
