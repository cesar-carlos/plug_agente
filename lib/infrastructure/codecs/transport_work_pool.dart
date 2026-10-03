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
  TransportWorkPool({int? workerCount, TransportWorkerSpawner? spawnWorker})
    : _workerCount = (workerCount ?? ConnectionConstants.transportWorkerPoolSize).clamp(1, 4),
      _spawnWorker = spawnWorker ?? _spawnTransportWorker;

  static final TransportWorkPool shared = TransportWorkPool();

  final int _workerCount;
  final TransportWorkerSpawner _spawnWorker;
  final List<_TransportWorker> _workers = <_TransportWorker>[];
  final Queue<_TransportWorkJob<dynamic>> _queue = Queue<_TransportWorkJob<dynamic>>();
  Future<void>? _starting;
  bool _disposed = false;
  Object? _fatalError;
  Future<void>? _shutdown;

  int submittedJobs = 0;
  int completedJobs = 0;
  int failedJobs = 0;
  int cancelledJobs = 0;
  int queueWaitMicroseconds = 0;
  int get activeJobs => _workers.where((worker) => worker.active != null).length;
  int get queuedJobs => _queue.length;
  int get workerCount => _workerCount;
  int get liveWorkers => _workers.where((worker) => worker.sendPort != null).length;
  int get openReplyPorts => activeJobs;

  Future<T> submit<T>(TransportWorkOperation operation, Object? payload) {
    if (_disposed) {
      return Future<T>.error(StateError('Transport work pool has been disposed'));
    }
    if (_fatalError case final error?) return Future<T>.error(error);
    submittedJobs++;
    final completer = Completer<T>();
    _queue.add(_TransportWorkJob<T>(operation, payload, completer));
    _ensureStarted();
    return completer.future;
  }

  void _ensureStarted() {
    _starting ??= _startWorkers().catchError(_failPool).whenComplete(_schedule);
    _schedule();
  }

  Future<void> _startWorkers() async {
    for (var index = 0; index < _workerCount; index++) {
      if (_disposed || _fatalError != null) return;
      final worker = _TransportWorker();
      _workers.add(worker);
      worker.readySubscription = worker.readyPort.listen((dynamic message) {
        if (message is! SendPort) {
          _failPool(StateError('Invalid transport worker handshake'), StackTrace.current);
          return;
        }
        worker.sendPort = message;
        if (!worker.ready.isCompleted) worker.ready.complete();
      });
      worker.errorSubscription = worker.errorPort.listen((dynamic error) {
        _failPool(StateError('Transport worker failed: $error'), StackTrace.current);
      });
      worker.exitSubscription = worker.exitPort.listen((dynamic _) {
        _failPool(StateError('Transport worker exited unexpectedly'), StackTrace.current);
      });
      final isolate = await _spawnWorker(
        worker.readyPort.sendPort,
        worker.errorPort.sendPort,
        worker.exitPort.sendPort,
      );
      worker.isolate = isolate;
      if (worker.closed) {
        isolate.kill(priority: Isolate.immediate);
        return;
      }
      await worker.ready.future;
      worker.readyPort.close();
      await worker.readySubscription?.cancel();
      if (worker.closed) {
        isolate.kill(priority: Isolate.immediate);
        return;
      }
    }
  }

  void _schedule() {
    if (_disposed || _fatalError != null || _workers.isEmpty) return;
    for (final worker in _workers) {
      if (worker.active != null || worker.sendPort == null || worker.closed || _queue.isEmpty) continue;
      final job = _queue.removeFirst();
      _run(worker, job);
    }
  }

  void _run<T>(_TransportWorker worker, _TransportWorkJob<T> job) {
    queueWaitMicroseconds += job.wait.elapsedMicroseconds;
    final active = _ActiveTransportWork<T>(job);
    worker.active = active;
    active.subscription = active.reply.listen((dynamic message) {
      if (worker.closed || worker.active != active || job.completer.isCompleted) return;
      active.close();
      worker.active = null;
      if (message is! List || message.length != 2 || message[0] is! bool) {
        job.completer.completeError(StateError('Invalid transport worker result'));
        failedJobs++;
        _failPool(StateError('Invalid transport worker result'), StackTrace.current);
        return;
      }
      completedJobs++;
      if (message[0] == true) {
        try {
          job.completer.complete(message[1] as T);
        } on Object catch (error, stack) {
          failedJobs++;
          job.completer.completeError(error, stack);
          _failPool(error, stack);
          return;
        }
      } else {
        failedJobs++;
        job.completer.completeError(StateError(message[1].toString()));
      }
      _schedule();
    });
    try {
      worker.sendPort!.send(<Object?>[active.reply.sendPort, job.operation.index, job.payload]);
    } on Object catch (error, stack) {
      _failPool(error, stack);
    }
  }

  void _failPool(Object error, StackTrace stack) {
    if (_disposed || _fatalError != null) return;
    _fatalError = error;
    _abortAll(error, stack, cancelled: false);
  }

  void _abortAll(Object error, StackTrace stack, {required bool cancelled}) {
    void fail(_TransportWorkJob<dynamic> job) {
      if (job.completer.isCompleted) return;
      if (cancelled) {
        cancelledJobs++;
      } else {
        failedJobs++;
      }
      job.completer.completeError(error, stack);
    }

    _queue.forEach(fail);
    _queue.clear();
    for (final worker in _workers) {
      if (worker.active case final active?) fail(active.job);
      worker.close();
    }
    _workers.clear();
  }

  Future<void> dispose() => _shutdown ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _abortAll(StateError('Transport work pool has been disposed'), StackTrace.current, cancelled: true);
    await _starting;
  }
}

class _TransportWorker {
  Isolate? isolate;
  SendPort? sendPort;
  final readyPort = ReceivePort();
  final errorPort = ReceivePort();
  final exitPort = ReceivePort();
  final ready = Completer<void>();
  StreamSubscription<dynamic>? readySubscription;
  StreamSubscription<dynamic>? errorSubscription;
  StreamSubscription<dynamic>? exitSubscription;
  _ActiveTransportWork<dynamic>? active;
  bool closed = false;

  void close() {
    if (closed) return;
    closed = true;
    if (!ready.isCompleted) ready.complete();
    active?.close();
    active = null;
    readyPort.close();
    errorPort.close();
    exitPort.close();
    unawaited(readySubscription?.cancel());
    unawaited(errorSubscription?.cancel());
    unawaited(exitSubscription?.cancel());
    isolate?.kill(priority: Isolate.immediate);
    sendPort = null;
  }
}

typedef TransportWorkerSpawner = Future<Isolate> Function(SendPort ready, SendPort errors, SendPort exit);

Future<Isolate> _spawnTransportWorker(SendPort ready, SendPort errors, SendPort exit) =>
    Isolate.spawn<SendPort>(_transportWorkerMain, ready, onError: errors, onExit: exit);

class _ActiveTransportWork<T> {
  _ActiveTransportWork(this.job);
  final _TransportWorkJob<T> job;
  final reply = ReceivePort();
  StreamSubscription<dynamic>? subscription;
  void close() {
    reply.close();
    unawaited(subscription?.cancel());
  }
}

class _TransportWorkJob<T> {
  _TransportWorkJob(this.operation, this.payload, this.completer);

  final TransportWorkOperation operation;
  final Object? payload;
  final Completer<T> completer;
  final Stopwatch wait = Stopwatch()..start();
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
