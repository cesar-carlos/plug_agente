import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:windows_action_runtime/src/windows_pipe_reader.dart';

/// Four credits per stream bound stdout and stderr to eight native blocks.
final class WindowsBoundedPipeOutput {
  WindowsBoundedPipeOutput(int address, {WindowsPipeReadApi? nativeApi}) {
    _responses.listen((message) {
      switch (message) {
        case final SendPort commands:
          _ready.complete(commands);
        case final Uint8List bytes:
          _events.add(bytes);
        case (final Object error, final StackTrace stack):
          if (!_ready.isCompleted) _ready.completeError(error, stack);
          _events.addError(error, stack);
        case null:
          _responses.close();
          unawaited(_events.close());
      }
    });
    unawaited(_ready.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    _completion = _launch(address, _responses.sendPort, nativeApi);
    unawaited(
      _completion.catchError((Object error, StackTrace stack) {
        _responses.sendPort.send((error, stack));
        _responses.sendPort.send(null);
      }),
    );
    stream = _consume();
  }

  static const blockBytes = 65536;
  static const streamCredits = 4;
  final ReceivePort _responses = ReceivePort();
  final StreamController<List<int>> _events = StreamController<List<int>>();
  final Completer<SendPort> _ready = Completer<SendPort>();
  late final Future<void> _completion;
  late final Stream<List<int>> stream;
  Future<void>? _closing;

  Stream<List<int>> _consume() async* {
    try {
      final commands = await _ready.future;
      for (var i = 0; i < streamCredits; i++) {
        commands.send(true);
      }
      await for (final bytes in _events.stream) {
        yield bytes;
        commands.send(true);
      }
    } finally {
      await close();
    }
  }

  /// The process tree must be stopped first if a native read is blocked.
  /// A caller timeout cannot release the descriptor owned by that read.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      (await _ready.future).send(null);
    } finally {
      try {
        await _completion;
      } finally {
        _responses.close();
        unawaited(_events.close());
      }
    }
  }
}

Future<void> _launch(int address, SendPort destination, WindowsPipeReadApi? nativeApi) async {
  final lifecycle = ReceivePort();
  try {
    try {
      await Isolate.spawn(
        _read,
        (address, destination, nativeApi),
        onExit: lifecycle.sendPort,
        onError: lifecycle.sendPort,
      );
    } on Object {
      CloseHandle(HANDLE(Pointer.fromAddress(address)));
      rethrow;
    }
    ProcessException? failure;
    await for (final event in lifecycle) {
      if (event == null) break;
      failure = const ProcessException('', [], 'Action output worker stopped unexpectedly');
    }
    if (failure != null) throw failure;
  } finally {
    lifecycle.close();
  }
}

Future<void> _read((int, SendPort, WindowsPipeReadApi?) arguments) async {
  final (address, destination, nativeApi) = arguments;
  final commands = ReceivePort();
  WindowsPipeReader? reader;
  Object? failure;
  StackTrace? failureStack;
  final buffer = calloc<Uint8>(WindowsBoundedPipeOutput.blockBytes);
  try {
    reader = WindowsPipeReader.takeOwnership(address, nativeApi: nativeApi);
    destination.send(commands.sendPort);
    await for (final command in commands) {
      if (command == null) break;
      if (command != true) throw StateError('Invalid output worker credit.');
      final count = reader.read(buffer, WindowsBoundedPipeOutput.blockBytes);
      if (count == 0) break;
      destination.send(Uint8List.fromList(buffer.asTypedList(count)));
    }
  } on Object catch (error, stack) {
    failure = error;
    failureStack = stack;
  } finally {
    try {
      reader?.close();
    } on Object catch (error, stack) {
      failure = failure == null ? error : WindowsPipeReadCleanupException(failure, error);
      failureStack ??= stack;
    }
    calloc.free(buffer);
    commands.close();
    if (failure != null) destination.send((failure, failureStack!));
    destination.send(null);
  }
}
