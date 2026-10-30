import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:plug_agente/domain/repositories/i_action_io_input_pipe.dart';
import 'package:result_dart/result_dart.dart';
import 'package:windows_action_runtime/windows_action_runtime.dart';

final class ActionIoProcessInputPipe implements IActionIoInputPipe {
  ActionIoProcessInputPipe(this._sink) {
    unawaited(
      _sink.done.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          _sinkFailure = error;
        },
      ),
    );
  }
  final IOSink _sink;
  Object? _sinkFailure;

  @override
  Future<Result<Unit>> write(Uint8List bytes) async {
    if (_sinkFailure != null) return Failure(ActionIoPipeFailure(cause: _sinkFailure));
    try {
      _sink.add(bytes);
      await _sink.flush();
      return const Success(unit);
    } on WindowsPipeWriteException catch (error) {
      _sinkFailure = error;
      return Failure(ActionIoPipeFailure(confirmedBytes: error.confirmedBytes, cause: error));
    } on Object catch (error) {
      _sinkFailure = error;
      return Failure(ActionIoPipeFailure(cause: error));
    }
  }

  @override
  Future<Result<Unit>> close() async {
    try {
      await _sink.close();
      return const Success(unit);
    } on Object catch (error) {
      return Failure(ActionIoPipeFailure(cause: error));
    }
  }
}
