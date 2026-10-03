import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/i_odbc_batched_streaming_query_source.dart';
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

  test('openRowMajor with named parameters uses the public service even with a native id', () async {
    when(
      () => service.streamQueryNamed(
        any(),
        any(),
        any(),
        fetchSize: any(named: 'fetchSize'),
        chunkSize: any(named: 'chunkSize'),
      ),
    ).thenAnswer(
      (_) => Stream.value(
        const Success(
          QueryResult(
            columns: ['id'],
            rows: [
              [42],
            ],
            rowCount: 1,
          ),
        ),
      ),
    );
    final first = await opener
        .openRowMajor(
          connectionId: '7',
          query: 'SELECT @id',
          parameters: const {'id': 42},
          nativeStreamingOptions: options,
        )
        .first;
    expect(first.getOrThrow().rows, [
      [42],
    ]);
    verify(
      () => service.streamQueryNamed(
        '7',
        'SELECT @id',
        {'id': 42},
        fetchSize: options.fetchSize,
        chunkSize: options.nativeChunkSizeBytes,
      ),
    ).called(1);
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

  test('openRowMajor with params falls back to streamQueryNamed without native id', () async {
    when(
      () => service.streamQueryNamed(
        any(),
        any(),
        any(),
        fetchSize: any(named: 'fetchSize'),
        chunkSize: any(named: 'chunkSize'),
      ),
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
    verify(
      () => service.streamQueryNamed(
        'pool-abc',
        any(),
        {'id': 1},
        fetchSize: options.fetchSize,
        chunkSize: options.nativeChunkSizeBytes,
      ),
    ).called(1);
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

  test('openRowMajor without params falls back to streamQuery forwarding knobs', () async {
    when(
      () => service.streamQuery(
        any(),
        any(),
        fetchSize: any(named: 'fetchSize'),
        chunkSize: any(named: 'chunkSize'),
      ),
    ).thenAnswer(
      (_) => Stream<Result<QueryResult>>.fromIterable([
        const Success(
          QueryResult(columns: ['id'], rows: [], rowCount: 0),
        ),
      ]),
    );

    final stream = opener.openRowMajor(
      connectionId: 'pool-abc',
      query: 'SELECT 1 AS id',
      nativeStreamingOptions: options,
    );

    await stream.first;
    verify(
      () => service.streamQuery(
        'pool-abc',
        'SELECT 1 AS id',
        fetchSize: options.fetchSize,
        chunkSize: options.nativeChunkSizeBytes,
      ),
    ).called(1);
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

  test('openColumnar with named parameters converts only for a columnar consumer', () async {
    when(
      () => service.streamQueryNamed(
        any(),
        any(),
        any(),
        fetchSize: any(named: 'fetchSize'),
        chunkSize: any(named: 'chunkSize'),
      ),
    ).thenAnswer(
      (_) => Stream.value(
        const Success(
          QueryResult(
            columns: ['v'],
            rows: [
              [1],
            ],
            rowCount: 1,
          ),
        ),
      ),
    );
    final result = await opener
        .openColumnar(
          connectionId: '9',
          query: 'SELECT @v AS v',
          nativeStreamingOptions: options,
          parameters: const {'v': 1},
        )
        .first;
    expect(result.getOrThrow().rowCount, 1);
    verify(
      () => service.streamQueryNamed(
        '9',
        'SELECT @v AS v',
        {'v': 1},
        fetchSize: options.fetchSize,
        chunkSize: options.nativeChunkSizeBytes,
      ),
    ).called(1);
  });

  test('openColumnar without params falls back to streamQueryColumnar forwarding knobs', () async {
    when(
      () => service.streamQueryColumnar(
        any(),
        any(),
        fetchSize: any(named: 'fetchSize'),
        chunkSize: any(named: 'chunkSize'),
      ),
    ).thenAnswer(
      (_) => Stream<Result<TypedColumnarResult>>.fromIterable([
        Success(toTypedColumnar(const QueryResult(columns: ['v'], rows: [], rowCount: 0))),
      ]),
    );

    final stream = opener.openColumnar(
      connectionId: 'pool-abc',
      query: 'SELECT 1 AS v',
      nativeStreamingOptions: options,
    );

    await stream.first;
    verify(
      () => service.streamQueryColumnar(
        'pool-abc',
        'SELECT 1 AS v',
        fetchSize: options.fetchSize,
        chunkSize: options.nativeChunkSizeBytes,
      ),
    ).called(1);
    verifyNever(
      () => batched.streamColumnarQuery(
        any(),
        any(),
        any(),
        namedParameters: any(named: 'namedParameters'),
      ),
    );
  });
}
