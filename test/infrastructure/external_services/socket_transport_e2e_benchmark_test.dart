@Tags(['benchmark'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_client_v2.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';

import '../../../tool/e2e_benchmark_summary.dart';
import '../../helpers/e2e_benchmark_assertions.dart';
import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

const String _caseRpcRoundTrip = 'socket_transport_e2e_rpc_roundtrip';
const String _caseAckRetry = 'socket_transport_e2e_ack_retry';
const String _caseStreamingBackpressure =
    'socket_transport_e2e_streaming_backpressure';

class MockSocketDataSource extends Mock implements SocketDataSource {}

class MockProtocolNegotiator extends Mock implements ProtocolNegotiator {}

class MockRpcMethodDispatcher extends Mock implements RpcMethodDispatcher {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockSocket extends Mock implements io.Socket {}

bool _envFlag(String key) => E2EEnv.get(key) == 'true';

double? _nonNegativeDoubleEnv(String key) {
  final raw = E2EEnv.get(key);
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final parsed = double.tryParse(raw);
  if (parsed == null || parsed < 0) {
    return null;
  }
  return parsed;
}

int _positiveIntEnv(String key, int fallback) {
  final raw = E2EEnv.get(key);
  final parsed = int.tryParse(raw ?? '');
  if (parsed == null || parsed <= 0) {
    return fallback;
  }
  return parsed;
}

String _outputFile() {
  final raw = E2EEnv.get('SOCKET_TRANSPORT_E2E_BENCHMARK_FILE')?.trim();
  if (raw != null && raw.isNotEmpty) {
    return raw;
  }
  return 'benchmark${Platform.pathSeparator}socket_transport_e2e.jsonl';
}

String? _baselineFile() {
  final raw = E2EEnv.get(
    'SOCKET_TRANSPORT_E2E_BENCHMARK_BASELINE_FILE',
  )?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return raw;
}

int _baselineWindow() {
  return _positiveIntEnv('SOCKET_TRANSPORT_E2E_BENCHMARK_BASELINE_WINDOW', 5);
}

bool _requireBaseline() {
  return _envFlag('SOCKET_TRANSPORT_E2E_BENCHMARK_REQUIRE_BASELINE');
}

/// When `SOCKET_TRANSPORT_E2E_BENCHMARK_STRICT_OUTGOING_CONTRACT=false`,
/// skips full outgoing RPC contract validation (faster; default validates).
bool _strictOutgoingContract() {
  final raw =
      E2EEnv.get('SOCKET_TRANSPORT_E2E_BENCHMARK_STRICT_OUTGOING_CONTRACT')
          ?.trim()
          .toLowerCase();
  if (raw == 'false') {
    return false;
  }
  return true;
}

Map<String, int> _maxMsByCase() {
  final out = <String, int>{};
  void add(String suffix, String caseKey) {
    final raw = E2EEnv.get(
      'SOCKET_TRANSPORT_E2E_BENCHMARK_MAX_MS_$suffix',
    )?.trim();
    final parsed = int.tryParse(raw ?? '');
    if (parsed != null && parsed > 0) {
      out[caseKey] = parsed;
    }
  }

  add('RPC_ROUNDTRIP', _caseRpcRoundTrip);
  add('ACK_RETRY', _caseAckRetry);
  add('STREAMING_BACKPRESSURE', _caseStreamingBackpressure);
  return out;
}

String _e2eSocketTransportBenchmarkBuildMode() {
  if (kReleaseMode) {
    return 'release';
  }
  if (kProfileMode) {
    return 'profile';
  }
  return 'debug';
}

List<Map<String, dynamic>> _loadBaselineRecords(String configuredPath) {
  final file = resolveE2eBenchmarkOutputFile(configuredPath);
  if (!file.existsSync()) {
    return const <Map<String, dynamic>>[];
  }
  final lines = file.readAsLinesSync().where((String line) {
    return line.trim().isNotEmpty;
  });
  return parseE2eBenchmarkJsonlLines(lines);
}

Map<String, dynamic> _encodeWirePayload(dynamic payload) {
  final frame = TransportPipeline(
    encoding: 'json',
    compression: 'gzip',
  ).prepareSend(payload).getOrThrow();
  return frame.toJson();
}

dynamic _decodeWirePayload(dynamic payload) {
  if (payload is! Map<String, dynamic> ||
      !payload.containsKey('schemaVersion')) {
    return payload;
  }
  final frame = PayloadFrame.fromJson(payload);
  final decoded = TransportPipeline(
    encoding: frame.enc,
    compression: frame.cmp,
    schemaVersion: frame.schemaVersion,
  ).receiveProcess(frame);
  expect(decoded.isSuccess(), isTrue);
  return decoded.getOrThrow();
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadLiveTestEnv();

  if (!_envFlag('SOCKET_TRANSPORT_E2E_BENCHMARK')) {
    group('Socket transport E2E benchmark', () {
      test(
        'skipped — enable SOCKET_TRANSPORT_E2E_BENCHMARK=true to run',
        () {},
        skip:
            'Defina SOCKET_TRANSPORT_E2E_BENCHMARK=true no .env para rodar o '
            'benchmark E2E do transporte Socket.',
      );
    });
    return;
  }

  setUpAll(() {
    registerFallbackValue(
      const RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
      ),
    );
    registerFallbackValue(ProtocolCapabilities.defaultCapabilities());
    registerFallbackValue(const TransportLimits());
  });

  group('Socket transport E2E benchmark', () {
    test(
      'should measure real transport request/ack/stream backpressure paths',
      () async {
        final dataSource = MockSocketDataSource();
        final negotiator = MockProtocolNegotiator();
        final dispatcher = MockRpcMethodDispatcher();
        final featureFlags = MockFeatureFlags();
        final socket = MockSocket();
        final metrics = MetricsCollector()..clear();

        final handlers = <String, Function>{};
        final emitted = <({String event, dynamic data})>[];
        final responseWaiters = <String, Completer<void>>{};
        final completeWaiters = <String, Completer<void>>{};
        var forceAckRetry = false;
        var ackFailuresRemaining = 0;

        void completeResponseIfNeeded(dynamic data) {
          if (data is! Map<String, dynamic>) {
            return;
          }
          final decoded = _decodeWirePayload(data);
          if (decoded is! Map<String, dynamic>) {
            return;
          }
          final id = decoded['id']?.toString();
          if (id == null) {
            return;
          }
          final waiter = responseWaiters.remove(id);
          waiter?.complete();
        }

        void completeStreamIfNeeded(dynamic data) {
          if (data is! Map<String, dynamic>) {
            return;
          }
          final decoded = _decodeWirePayload(data);
          if (decoded is! Map<String, dynamic>) {
            return;
          }
          final requestId = decoded['request_id']?.toString();
          if (requestId == null) {
            return;
          }
          final waiter = completeWaiters.remove(requestId);
          waiter?.complete();
        }

        when(
          () => dataSource.createSocket(
            any(),
            authToken: any(named: 'authToken'),
          ),
        ).thenReturn(socket);
        when(() => socket.connected).thenReturn(true);
        when(socket.connect).thenReturn(socket);
        when(socket.disconnect).thenReturn(socket);
        when(socket.dispose).thenReturn(null);
        when(() => socket.on(any<String>(), any())).thenAnswer((invocation) {
          handlers[invocation.positionalArguments[0] as String] =
              invocation.positionalArguments[1] as Function;
          return () {};
        });
        when(() => socket.emit(any<String>(), any<dynamic>())).thenAnswer((
          invocation,
        ) {
          final event = invocation.positionalArguments[0] as String;
          final data = invocation.positionalArguments[1];
          emitted.add((event: event, data: data));
          if (event == 'rpc:response') {
            completeResponseIfNeeded(data);
          } else if (event == 'rpc:complete') {
            completeStreamIfNeeded(data);
          }
        });
        when(() => socket.timeout(any<int>())).thenReturn(socket);
        when(
          () => socket.emitWithAckAsync(any<String>(), any<dynamic>()),
        ).thenAnswer((invocation) async {
          final event = invocation.positionalArguments[0] as String;
          final data = invocation.positionalArguments[1];
          if (event == 'rpc:response' &&
              forceAckRetry &&
              ackFailuresRemaining > 0) {
            ackFailuresRemaining--;
            throw Exception('ack timeout');
          }
          emitted.add((event: event, data: data));
          if (event == 'rpc:response') {
            completeResponseIfNeeded(data);
          } else if (event == 'rpc:complete') {
            completeStreamIfNeeded(data);
          }
        });

        when(() => featureFlags.enableSocketBackpressure).thenReturn(true);
        when(() => featureFlags.enableBinaryPayload).thenReturn(true);
        when(() => featureFlags.enableCompression).thenReturn(true);
        when(() => featureFlags.outboundCompressionMode).thenReturn(
          OutboundCompressionMode.gzip,
        );
        when(() => featureFlags.compressionThreshold).thenReturn(1024);
        when(() => featureFlags.enableSocketSchemaValidation).thenReturn(false);
        when(
          () => featureFlags.enableSocketOutgoingContractValidation,
        ).thenReturn(_strictOutgoingContract());
        when(
          () => featureFlags.enableSocketSummarizeLargePayloadLogs,
        ).thenReturn(false);
        when(
          () => featureFlags.enableSocketDeliveryGuarantees,
        ).thenReturn(true);
        when(
          () => featureFlags.enableSocketNotificationsContract,
        ).thenReturn(true);
        when(() => featureFlags.enableSocketStreamingChunks).thenReturn(true);
        when(() => featureFlags.enableSocketBatchStrictValidation).thenReturn(
          true,
        );
        when(() => featureFlags.enableSocketApiVersionMeta).thenReturn(false);
        when(() => featureFlags.enablePayloadSigning).thenReturn(false);
        when(
          () => featureFlags.enableClientTokenAuthorization,
        ).thenReturn(false);
        when(() => featureFlags.enableSocketIdempotency).thenReturn(false);
        when(() => featureFlags.enableSocketTimeoutByStage).thenReturn(false);
        when(() => featureFlags.enableSocketStreamingFromDb).thenReturn(false);
        when(() => featureFlags.enableSocketCancelMethod).thenReturn(false);
        when(() => featureFlags.enablePerRequestOutboundCompression).thenReturn(
          true,
        );
        when(
          () => featureFlags.enableSocketOutboundCompressionDebugLog,
        ).thenReturn(false);

        when(
          () => negotiator.negotiate(
            agentCapabilities: any(named: 'agentCapabilities'),
            serverCapabilities: any(named: 'serverCapabilities'),
            preferJsonRpcV2: any(named: 'preferJsonRpcV2'),
          ),
        ).thenReturn(
          const ProtocolConfig(
            protocol: 'jsonrpc-v2',
            encoding: 'json',
            compression: 'gzip',
            signatureAlgorithms: ['hmac-sha256'],
            negotiatedExtensions: {
              'binaryPayload': true,
              'transportFrame': 'payload-frame/1.0',
              'notificationNullIdCompatibility': true,
              'signatureRequired': false,
              'signatureAlgorithms': ['hmac-sha256'],
            },
          ),
        );

        when(
          dispatcher.cancelActiveStreamOnDisconnect,
        ).thenAnswer((_) async {});
        when(
          () => dispatcher.dispatch(
            any(),
            any(),
            clientToken: any(named: 'clientToken'),
            streamEmitter: any(named: 'streamEmitter'),
            limits: any(named: 'limits'),
            negotiatedExtensions: any(named: 'negotiatedExtensions'),
          ),
        ).thenAnswer((Invocation invocation) async {
          final req = invocation.positionalArguments[0] as RpcRequest;
          final id = req.id?.toString() ?? 'unknown';
          if (id.startsWith('stream-')) {
            final emitter =
                invocation.namedArguments[const Symbol('streamEmitter')]
                    as IRpcStreamEmitter?;
            expect(emitter, isNotNull);
            for (var i = 0; i < 4; i++) {
              await emitter!.emitChunk(
                RpcStreamChunk(
                  streamId: 'stream-$id',
                  requestId: id,
                  chunkIndex: i,
                  rows: <Map<String, dynamic>>[
                    <String, dynamic>{'id': i + 1, 'code': 'row_${i + 1}'},
                  ],
                  totalChunks: 4,
                ),
              );
            }
            await emitter!.emitComplete(
              RpcStreamComplete(
                streamId: 'stream-$id',
                requestId: id,
                totalRows: 4,
              ),
            );
            return RpcResponse.success(
              id: id,
              result: <String, dynamic>{
                'stream_id': 'stream-$id',
                'rows': <Map<String, dynamic>>[],
                'row_count': 0,
              },
            );
          }

          return RpcResponse.success(
            id: id,
            result: <String, dynamic>{'ok': true},
          );
        });

        final client = SocketIOTransportClientV2(
          dataSource: dataSource,
          negotiator: negotiator,
          rpcDispatcher: dispatcher,
          featureFlags: featureFlags,
          metricsCollector: metrics,
        );

        final connectFuture = client.connect('https://hub.test', 'agent-bench');
        Function.apply(handlers['connect']!, const [null]);
        await connectFuture;
        Function.apply(handlers['agent:capabilities']!, [
          _encodeWirePayload(<String, dynamic>{
            'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
          }),
        ]);
        emitted.clear();

        var seq = 0;
        String nextId(String prefix) => '$prefix-${seq++}';

        Future<void> dispatchAndWait(String id, {bool stream = false}) async {
          final responseCompleter = Completer<void>();
          responseWaiters[id] = responseCompleter;
          if (stream) {
            completeWaiters[id] = Completer<void>();
          }

          Function.apply(handlers['rpc:request']!, [
            _encodeWirePayload(<String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'sql.execute',
              'id': id,
              'params': <String, dynamic>{
                'sql': stream ? 'SELECT * FROM t_stream' : 'SELECT 1',
              },
            }),
          ]);

          if (stream) {
            await Future<void>.delayed(const Duration(milliseconds: 2));
            Function.apply(handlers['rpc:stream.pull']!, [
              _encodeWirePayload(<String, dynamic>{
                'stream_id': 'stream-$id',
                'window_size': 4,
              }),
            ]);
          }

          await responseCompleter.future.timeout(const Duration(seconds: 2));
          if (stream) {
            await completeWaiters[id]!.future.timeout(
              const Duration(seconds: 2),
            );
          }
        }

        final rpcRoundTrip = await E2eBenchmarkStats.measureAsync(
          () async {
            await dispatchAndWait(nextId('rpc'));
          },
          warmup: 1,
        );

        final ackRetry = await E2eBenchmarkStats.measureAsync(
          () async {
            forceAckRetry = true;
            ackFailuresRemaining = _positiveIntEnv(
              'SOCKET_TRANSPORT_E2E_BENCHMARK_ACK_FAILS',
              1,
            );
            try {
              await dispatchAndWait(nextId('ack'));
            } finally {
              forceAckRetry = false;
              ackFailuresRemaining = 0;
            }
          },
          warmup: 1,
          iterations: 6,
        );

        // Isolate streaming phase from ack-retry callbacks / pending futures.
        await Future<void>.delayed(const Duration(milliseconds: 25));

        final streamingBackpressure = await E2eBenchmarkStats.measureAsync(
          () async {
            await dispatchAndWait(nextId('stream'), stream: true);
          },
          warmup: 1,
          iterations: 4,
        );

        final cases = <String, dynamic>{
          _caseRpcRoundTrip: rpcRoundTrip.toJson(),
          _caseAckRetry: <String, dynamic>{
            ...ackRetry.toJson(),
            'ack_retry_count_delta': metrics.rpcResponseAckRetryCount,
            'ack_fallback_without_ack_delta':
                metrics.rpcResponseAckFallbackWithoutAckCount,
          },
          _caseStreamingBackpressure: <String, dynamic>{
            ...streamingBackpressure.toJson(),
            'transport_decode_sync_delta':
                metrics.transportInboundDecodeSyncCount,
            'transport_decode_async_delta':
                metrics.transportInboundDecodeAsyncCount,
            'terminal_complete_emitted_delta':
                metrics.rpcStreamTerminalCompleteEmittedCount,
          },
        };

        final thresholds = _maxMsByCase();
        if (thresholds.isNotEmpty) {
          assertE2eBenchmarkWithinThresholds(
            cases: cases,
            thresholds: thresholds,
          );
        }

        final baselineFile = _baselineFile();
        final maxRegressionPercent = _nonNegativeDoubleEnv(
          'SOCKET_TRANSPORT_E2E_BENCHMARK_MAX_REGRESSION_PERCENT',
        );
        if (baselineFile != null && maxRegressionPercent != null) {
          final comparableBaseline = selectComparableE2eBenchmarkRecords(
            records: _loadBaselineRecords(baselineFile),
            targetLabel: 'socket_transport_e2e',
            buildMode: _e2eSocketTransportBenchmarkBuildMode(),
            benchmarkProfile: <String, dynamic>{
              'ack_failures': _positiveIntEnv(
                'SOCKET_TRANSPORT_E2E_BENCHMARK_ACK_FAILS',
                1,
              ),
              'stream_chunks': 4,
              'strict_outgoing_contract': _strictOutgoingContract(),
            },
          );
          if (_requireBaseline()) {
            expect(
              comparableBaseline,
              isNotEmpty,
              reason:
                  'No comparable socket transport E2E baseline records found. '
                  'Record at least one run for the active benchmark profile.',
            );
          }
          if (comparableBaseline.isNotEmpty) {
            assertE2eBenchmarkWithinRegressionBudget(
              cases: cases,
              baselineRecords: comparableBaseline,
              maxRegressionPercent: maxRegressionPercent,
              maxRegressionMs: _positiveIntEnv(
                'SOCKET_TRANSPORT_E2E_BENCHMARK_MAX_REGRESSION_MS',
                2,
              ),
              window: _baselineWindow(),
            );
          }
        }

        if (_envFlag('SOCKET_TRANSPORT_E2E_BENCHMARK_RECORD')) {
          final out = resolveE2eBenchmarkOutputFile(_outputFile());
          appendE2eBenchmarkRecord(
            file: out,
            record: <String, dynamic>{
              'schema_version': 2,
              'suite': 'socket_transport_e2e_benchmark',
              'run_id': const Uuid().v4(),
              'recorded_at': DateTime.now().toUtc().toIso8601String(),
              'target_label': 'socket_transport_e2e',
              'build_mode': _e2eSocketTransportBenchmarkBuildMode(),
              'git_revision': resolveE2eGitRevision(),
              'dart_platform': Platform.operatingSystem,
              'dart_version': Platform.version.split('\n').first,
              'benchmark_profile': <String, dynamic>{
                'ack_failures': _positiveIntEnv(
                  'SOCKET_TRANSPORT_E2E_BENCHMARK_ACK_FAILS',
                  1,
                ),
                'stream_chunks': 4,
                'strict_outgoing_contract': _strictOutgoingContract(),
              },
              'cases': cases,
            },
          );
        }
      },
    );
  });
}
