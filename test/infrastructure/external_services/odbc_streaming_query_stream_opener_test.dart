import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/i_odbc_batched_streaming_query_source.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_named_streaming_params.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_native_options.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_query_stream_opener.dart';
import 'package:result_dart/result_dart.dart';

class _MockOdbcService extends Mock implements OdbcService {}

class _MockBatchedSource extends Mock implements IOdbcBatchedStreamingQuerySource {}

void main() {
  late _MockOdbcService service;
  late _MockBatchedSource batched;
  late OdbcStreamingQueryStreamOpener opener;
  final options = OdbcStreamingNativeOptions.resolve(
    fetchSize: 250,
    chunkSizeBytes: OdbcStreamingNativeOptions.hubStreamingChunkSizeBytes,
    settingsMaxResultBufferMb: 16,
  );

  setUpAll(() {
    registerFallbackValue(options);
  });

  setUp(() {
    service = _MockOdbcService();
    batched = _MockBatchedSource();
    opener = OdbcStreamingQueryStreamOpener(
      service: service,
      batchedQuerySource: batched,
    );
  });

  test('prepareNamedStreamingParams cleans SQL and builds a params buffer', () {
    final prepared = prepareNamedStreamingParams(
      sql: 'SELECT * FROM t WHERE id = @id',
      namedParameters: const {'id': 42},
    );
    expect(prepared.cleanedSql.toLowerCase(), contains('?'));
    expect(prepared.paramsBuffer, isNotEmpty);
  });

  test('openRowMajor with params uses batched source and forwards knobs', () async {
    when(
      () => batched.streamRowMajorQuery(
        7,
        any(),
        any(),
        lazyStrings: any(named: 'lazyStrings'),
        namedParameters: any(named: 'namedParameters'),
      ),
    ).thenAnswer(
      (_) => Stream<Result<QueryResult>>.fromIterable([
        const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [42],
            ],
            rowCount: 1,
          ),
        ),
      ]),
    );

    final stream = opener.openRowMajor(
      connectionId: '7',
      query: 'SELECT * FROM t WHERE id = @id',
      nativeStreamingOptions: options,
      parameters: const {'id': 42},
      lazyStrings: true,
    );

    final first = await stream.first;
    expect(first.isSuccess(), isTrue);
    verify(
      () => batched.streamRowMajorQuery(
        7,
        'SELECT * FROM t WHERE id = @id',
        options,
        lazyStrings: true,
        namedParameters: {'id': 42},
      ),
    ).called(1);
    verifyNever(() => service.streamQueryNamed(any(), any(), any()));
  });

  test('openRowMajor with params falls back to streamQueryNamed without native id', () async {
    when(
      () => service.streamQueryNamed(any(), any(), any()),
    ).thenAnswer(
      (_) => Stream<Result<QueryResult>>.fromIterable([
        const Success(
          QueryResult(columns: ['id'], rows: [], rowCount: 0),
        ),
      ]),
    );

    final stream = opener.openRowMajor(
      connectionId: 'pool-abc',
      query: 'SELECT * FROM t WHERE id = @id',
      nativeStreamingOptions: options,
      parameters: const {'id': 1},
    );

    await stream.first;
    verify(() => service.streamQueryNamed('pool-abc', any(), {'id': 1})).called(1);
    verifyNever(
      () => batched.streamRowMajorQuery(
        any(),
        any(),
        any(),
        lazyStrings: any(named: 'lazyStrings'),
        namedParameters: any(named: 'namedParameters'),
      ),
    );
  });

  test('openColumnar with params uses batched source', () async {
    when(
      () => batched.streamColumnarQuery(
        9,
        any(),
        any(),
        namedParameters: any(named: 'namedParameters'),
      ),
    ).thenAnswer(
      (_) => Stream<Result<TypedColumnarResult>>.fromIterable([
        Success(toTypedColumnar(const QueryResult(columns: ['v'], rows: [], rowCount: 0))),
      ]),
    );

    final stream = opener.openColumnar(
      connectionId: '9',
      query: 'SELECT @v AS v',
      nativeStreamingOptions: options,
      parameters: const {'v': 1},
    );

    await stream.first;
    verify(
      () => batched.streamColumnarQuery(
        9,
        'SELECT @v AS v',
        options,
        namedParameters: {'v': 1},
      ),
    ).called(1);
  });
}
