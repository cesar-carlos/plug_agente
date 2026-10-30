import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:windows_action_runtime/src/windows_pipe_writer.dart';

/// Serializes bounded native writes on one worker which owns the pipe until EOF.
final class WindowsPipeInputSink implements StreamConsumer<List<int>> {
  /// An injected native API must be transferable to the worker isolate.
  /// The default resolves the system CRT inside that isolate.
  WindowsPipeInputSink(int address, {WindowsPipeWriteApi? nativeApi}) : _worker = _InputWorker(address, nativeApi);

  final _InputWorker _worker;
  Future<void>? _pending;
  Future<void>? _closing;
  (Object, StackTrace)? _failure;

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    if (_closing != null) throw StateError('Silent process stdin is closed.');
    if (_pending != null) throw StateError('Silent process stdin is already writing.');
    return _pending = _write(stream);
  }

  Future<void> _write(Stream<List<int>> stream) async {
    var confirmedBytes = 0;
    try {
      final failure = _failure;
      if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
      await for (final chunk in stream) {
        for (var offset = 0; offset < chunk.length; offset += _InputWorker.blockBytes) {
          final end = offset + _InputWorker.blockBytes;
          await _worker.write(Uint8List.fromList(chunk.sublist(offset, end < chunk.length ? end : chunk.length)));
          confirmedBytes += end < chunk.length ? _InputWorker.blockBytes : chunk.length - offset;
        }
      }
    } on WindowsPipeWriteException catch (error, stack) {
      final failure = WindowsPipeWriteException(
        confirmedBytes + error.confirmedBytes,
        cleanupFailure: error.cleanupFailure,
      );
      _failure ??= (failure, stack);
      Error.throwWithStackTrace(failure, stack);
    } on Object catch (error, stack) {
      _failure ??= (error, stack);
      rethrow;
    } finally {
      _pending = null;
    }
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await _pending;
    } on Object catch (error, stack) {
      _failure ??= (error, stack);
    }
    try {
      await _worker.close();
    } on Object catch (error, stack) {
      final primary = _failure;
      if (primary == null) {
        _failure = (error, stack);
      } else if (!identical(primary.$1, error)) {
        final original = primary.$1;
        _failure = (
          original is WindowsPipeWriteException
              ? WindowsPipeWriteException(original.confirmedBytes, cleanupFailure: error)
              : WindowsPipeCleanupException(original, error),
          primary.$2,
        );
      }
    }
    final failure = _failure;
    if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
  }
}

final class _InputWorker {
  _InputWorker(int address, WindowsPipeWriteApi? nativeApi) {
    _messages = StreamIterator<Object?>(_responses);
    _completion = _startWorker(address, _responses.sendPort, nativeApi);
    // Keep launch failures on the protocol path, including when stdin is unused.
    unawaited(
      _completion.catchError((Object error, StackTrace stack) {
        _launchFailure = (error, stack);
        _responses.sendPort.send(null);
      }),
    );
  }

  static const blockBytes = 65536;
  final ReceivePort _responses = ReceivePort();
  late final StreamIterator<Object?> _messages;
  late final Future<void> _completion;
  SendPort? _commands;
  bool _failed = false;
  (Object, StackTrace)? _launchFailure;

  Future<Object?> _response() async {
    if (!await _messages.moveNext()) throw StateError('Input worker stopped without acknowledgment.');
    if (_launchFailure case (final error, final stack)) {
      _failed = true;
      Error.throwWithStackTrace(error, stack);
    }
    final response = _messages.current;
    if (response case (final Object error, final StackTrace stack)) {
      _failed = true;
      Error.throwWithStackTrace(error, stack);
    }
    return response;
  }

  Future<SendPort> _ready() async {
    if (_commands case final port?) return port;
    final response = await _response();
    if (response is! SendPort) throw StateError('Invalid input worker handshake.');
    return _commands = response;
  }

  Future<void> write(Uint8List bytes) async {
    final commands = await _ready();
    commands.send(bytes);
    if (await _response() != bytes.length) throw StateError('Invalid input worker acknowledgment.');
  }

  Future<void> close() async {
    try {
      if (!_failed) {
        final commands = await _ready();
        commands.send(null);
        if (await _response() != null) throw StateError('Invalid input worker close acknowledgment.');
      }
      await _completion;
    } finally {
      // A timeout outside this class never closes or reuses the worker's handle.
      try {
        await _completion;
      } finally {
        _responses.close();
        await _messages.cancel();
      }
    }
  }
}

Future<void> _startWorker(int address, SendPort replies, WindowsPipeWriteApi? nativeApi) async {
  final lifecycle = ReceivePort();
  try {
    try {
      await Isolate.spawn(
        _inputEntry,
        (address, replies, nativeApi),
        onExit: lifecycle.sendPort,
        onError: lifecycle.sendPort,
      );
    } on Object catch (error, stack) {
      // Only a failed launch leaves ownership with the caller.
      final cleanupError = nativeApi != null
          ? nativeApi.releaseHandle(address)
          : (CloseHandle(HANDLE(Pointer.fromAddress(address))).value ? 0 : GetLastError().toInt());
      if (cleanupError != 0) {
        Error.throwWithStackTrace(WindowsPipeOwnershipException(error, cleanupError), stack);
      }
      rethrow;
    }
    ProcessException? failure;
    await for (final message in lifecycle) {
      if (message == null) break;
      failure = const ProcessException('', [], 'Action input worker stopped unexpectedly');
    }
    if (failure != null) throw failure;
  } finally {
    lifecycle.close();
  }
}

Future<void> _inputEntry((int, SendPort, WindowsPipeWriteApi?) arguments) =>
    _serveInput(arguments.$1, arguments.$2, arguments.$3);

Future<void> _serveInput(int address, SendPort replies, WindowsPipeWriteApi? nativeApi) async {
  final commands = ReceivePort();
  WindowsPipeWriter? writer;
  Object? failure;
  StackTrace? failureStack;
  try {
    writer = WindowsPipeWriter.takeOwnership(address, nativeApi: nativeApi);
    replies.send(commands.sendPort);
    await for (final command in commands) {
      if (command == null) break;
      if (command is! Uint8List || command.length > _InputWorker.blockBytes) {
        throw StateError('Invalid input worker block.');
      }
      using((arena) {
        final buffer = arena<Uint8>(command.length);
        buffer.asTypedList(command.length).setAll(0, command);
        writer!.write(buffer, command.length);
      });
      replies.send(command.length);
    }
  } on Object catch (error, stack) {
    failure = error;
    failureStack = stack;
  } finally {
    try {
      writer?.close();
    } on Object catch (error, stack) {
      final primary = failure;
      failure = switch (primary) {
        null => error,
        WindowsPipeWriteException() => WindowsPipeWriteException(primary.confirmedBytes, cleanupFailure: error),
        _ => WindowsPipeCleanupException(primary, error),
      };
      failureStack ??= stack;
    }
    commands.close();
    replies.send(failure == null ? null : (failure, failureStack!));
  }
}
