import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline_isolate.dart';
import 'package:plug_agente/infrastructure/security/payload_signing_canonicalizer.dart';

/// CPU operations run by [TransportWorkPool]. Payloads are limited by the
/// transport before they reach a worker.
enum TransportWorkOperation { jsonEncode, jsonDecode, gzipCompress, gzipDecompress, hmacSign, hmacVerify }

/// Reusable, bounded isolate workers for transport CPU work.
///
/// Workers are started lazily, so normal small frames keep the synchronous
/// path and do not pay an isolate startup cost. The queue provides a single
/// pressure point for JSON, GZIP and HMAC instead of spawning an isolate per
/// large frame.
class TransportWorkPool {
  TransportWorkPool({int? workerCount})
    : _workerCount = (workerCount ?? ConnectionConstants.transportWorkerPoolSize).clamp(1, 4);

  static final TransportWorkPool shared = TransportWorkPool();

  final int _workerCount;
  final List<_TransportWorker> _workers = <_TransportWorker>[];
  final Queue<_TransportWorkJob<dynamic>> _queue = Queue<_TransportWorkJob<dynamic>>();
  Future<void>? _starting;
  bool _disposed = false;

  int submittedJobs = 0;
  int completedJobs = 0;
  int get activeJobs => _workers.where((worker) => worker.busy).length;
  int get queuedJobs => _queue.length;
  int get workerCount => _workerCount;

  Future<T> submit<T>(TransportWorkOperation operation, Object? payload) {
    if (_disposed) {
      return Future<T>.error(StateError('Transport work pool has been disposed'));
    }
    submittedJobs++;
    final completer = Completer<T>();
    _queue.add(_TransportWorkJob<T>(operation, payload, completer));
    _ensureStarted();
    return completer.future;
  }

  void _ensureStarted() {
    _starting ??= _startWorkers();
    unawaited(_starting!.then((_) => _schedule()));
  }

  Future<void> _startWorkers() async {
    for (var index = 0; index < _workerCount; index++) {
      if (_disposed) return;
      final ready = ReceivePort();
      final isolate = await Isolate.spawn<SendPort>(_transportWorkerMain, ready.sendPort);
      final sendPort = await ready.first as SendPort;
      ready.close();
      _workers.add(_TransportWorker(isolate, sendPort));
    }
  }

  void _schedule() {
    if (_disposed || _workers.isEmpty) return;
    for (final worker in _workers) {
      if (worker.busy || _queue.isEmpty) continue;
      final job = _queue.removeFirst();
      _run(worker, job);
    }
  }

  void _run<T>(_TransportWorker worker, _TransportWorkJob<T> job) {
    worker.busy = true;
    final reply = ReceivePort();
    late final StreamSubscription<dynamic> subscription;
    subscription = reply.listen((dynamic message) {
      unawaited(subscription.cancel());
      reply.close();
      worker.busy = false;
      completedJobs++;
      final values = message as List<dynamic>;
      if (values[0] == true) {
        job.completer.complete(values[1] as T);
      } else {
        job.completer.completeError(StateError(values[1] as String));
      }
      _schedule();
    });
    worker.sendPort.send(<Object?>[reply.sendPort, job.operation.index, job.payload]);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final job in _queue) {
      job.completer.completeError(StateError('Transport work pool has been disposed'));
    }
    _queue.clear();
    for (final worker in _workers) {
      worker.isolate.kill(priority: Isolate.immediate);
    }
    _workers.clear();
  }
}

class _TransportWorker {
  _TransportWorker(this.isolate, this.sendPort);

  final Isolate isolate;
  final SendPort sendPort;
  bool busy = false;
}

class _TransportWorkJob<T> {
  _TransportWorkJob(this.operation, this.payload, this.completer);

  final TransportWorkOperation operation;
  final Object? payload;
  final Completer<T> completer;
}

void _transportWorkerMain(SendPort readyPort) {
  final receivePort = ReceivePort();
  readyPort.send(receivePort.sendPort);
  receivePort.listen((dynamic message) {
    final values = message as List<dynamic>;
    final reply = values[0] as SendPort;
    try {
      reply.send(<Object?>[true, _performTransportWork(TransportWorkOperation.values[values[1] as int], values[2])]);
    } on Object catch (error) {
      reply.send(<Object?>[false, error.toString()]);
    }
  });
}

Object _performTransportWork(TransportWorkOperation operation, Object? payload) {
  switch (operation) {
    case TransportWorkOperation.jsonEncode:
      return jsonUtf8EncodePayloadInIsolate(payload);
    case TransportWorkOperation.jsonDecode:
      return jsonDecodeUtf8PayloadInIsolate(payload! as Uint8List);
    case TransportWorkOperation.gzipCompress:
      return compressGzipInIsolate(payload! as Uint8List);
    case TransportWorkOperation.gzipDecompress:
      final values = payload! as List<dynamic>;
      return decompressGzipInIsolate((values[0] as Uint8List, values[1] as int));
    case TransportWorkOperation.hmacSign:
      final values = payload! as Map<dynamic, dynamic>;
      final frame = PayloadFrame.fromJson(Map<String, dynamic>.from(values['frame'] as Map));
      final key = values['key'] as Uint8List;
      final canonicalize = Stopwatch()..start();
      final canonicalBytes = PayloadSigningCanonicalizer.canonicalizeFrame(frame);
      canonicalize.stop();
      final sign = Stopwatch()..start();
      final value = base64Encode(Hmac(sha256, key).convert(canonicalBytes).bytes);
      sign.stop();
      return <String, Object>{
        'value': value,
        'keyId': values['keyId'] as String,
        'canonicalizeDurationUs': canonicalize.elapsedMicroseconds,
        'signDurationUs': sign.elapsedMicroseconds,
      };
    case TransportWorkOperation.hmacVerify:
      final values = payload! as Map<dynamic, dynamic>;
      final frame = PayloadFrame.fromJson(Map<String, dynamic>.from(values['frame'] as Map));
      final key = values['key'] as Uint8List;
      final canonicalize = Stopwatch()..start();
      final canonicalBytes = PayloadSigningCanonicalizer.canonicalizeFrame(frame);
      canonicalize.stop();
      final verify = Stopwatch()..start();
      final expected = base64Encode(Hmac(sha256, key).convert(canonicalBytes).bytes);
      final valid = _constantTimeEquals(expected, values['signature'] as String);
      verify.stop();
      return <String, Object>{
        'isValid': valid,
        'canonicalizeDurationUs': canonicalize.elapsedMicroseconds,
        'verifyDurationUs': verify.elapsedMicroseconds,
      };
  }
}

bool _constantTimeEquals(String expected, String actual) {
  try {
    final expectedBytes = base64Decode(_padBase64(expected));
    final actualBytes = base64Decode(_padBase64(actual));
    final length = expectedBytes.length > actualBytes.length ? expectedBytes.length : actualBytes.length;
    var difference = expectedBytes.length ^ actualBytes.length;
    for (var index = 0; index < length; index++) {
      difference |=
          (index < expectedBytes.length ? expectedBytes[index] : 0) ^
          (index < actualBytes.length ? actualBytes[index] : 0);
    }
    return difference == 0;
  } on FormatException {
    return false;
  }
}

String _padBase64(String value) {
  final remainder = value.length % 4;
  return remainder == 0 ? value : '$value${'=' * (4 - remainder)}';
}
