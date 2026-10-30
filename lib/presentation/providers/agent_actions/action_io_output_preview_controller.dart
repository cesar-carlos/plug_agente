import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_output.dart';

/// A single bounded display page. Text decoding never changes journal bytes.
class ActionIoOutputPreviewController extends ChangeNotifier {
  ActionIoOutputPreviewController(this._output, {required this.executionId});

  final IActionIoLocalOutput _output;
  final String executionId;
  bool _disposed = false;
  bool isLoading = false;
  bool hasLoaded = false;
  bool terminal = false;
  bool outputComplete = false;
  int nextSequence = 0;
  String stdoutText = '';
  String stderrText = '';
  String? errorCode;

  Future<void> loadNext() async {
    if (_disposed || isLoading) return;
    isLoading = true;
    errorCode = null;
    notifyListeners();
    final result = await _output.readLocalOutput(
      executionId: executionId,
      afterSequence: nextSequence,
      maxBytes: ActionIoLimits.blockBytes,
    );
    if (_disposed) return;
    result.fold(
      (page) {
        final stdout = <int>[];
        final stderr = <int>[];
        var bytes = 0;
        for (final event in page.events.whereType<ActionIoOutputEvent>()) {
          bytes += event.bytes.length;
          if (bytes > ActionIoLimits.blockBytes) {
            errorCode = 'ACTION_IO_PREVIEW_LIMIT';
            return;
          }
          (event.stream == ActionIoStream.stdout ? stdout : stderr).addAll(event.bytes);
        }
        stdoutText = utf8.decode(stdout, allowMalformed: true);
        stderrText = utf8.decode(stderr, allowMalformed: true);
        nextSequence = page.nextSequence;
        terminal = page.terminal;
        outputComplete = page.outputComplete;
        hasLoaded = true;
      },
      (failure) {
        if (failure is ActionFailure) {
          failure.log();
          errorCode = failure.code;
        } else {
          errorCode = 'ACTION_IO_PREVIEW_FAILED';
        }
      },
    );
    isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stdoutText = '';
    stderrText = '';
    super.dispose();
  }
}
