import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/bootstrap/odbc_application_runtime_reset_service.dart';
import 'package:plug_agente/domain/repositories/i_odbc_streaming_session_cache.dart';
import 'package:result_dart/result_dart.dart';

class _MockStreamingSessionCache extends Mock implements IOdbcStreamingSessionCache {}

void main() {
  test('resetForOdbcRuntimeReload drains cached streaming sessions', () async {
    final getIt = GetIt.asNewInstance();
    final cache = _MockStreamingSessionCache();
    when(cache.drainCachedSessions).thenAnswer((_) async => const Success(unit));
    getIt.registerSingleton<IOdbcStreamingSessionCache>(cache);

    final service = OdbcApplicationRuntimeResetService(getIt: getIt);
    await service.resetForOdbcRuntimeReload();

    verify(cache.drainCachedSessions).called(1);
    verifyNever(cache.invalidate);
  });
}
