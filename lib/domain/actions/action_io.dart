import 'dart:typed_data';

abstract final class ActionIoLimits {
  static const int version = 1;
  static const int blockBytes = 64 * 1024;
  static const int pageBytes = 256 * 1024;
  static const int pageEvents = 256;
  static const int jsonBytes = 512 * 1024;
  static const int executionBytes = 64 * 1024 * 1024;
  static const int queuedMessages = 16;
  static const int queuedBytes = 1024 * 1024;
  static const int executionMessages = 8192;
  static const int executionEvents = 65536;
  static const int terminalEventReserve = 2;
  static const int payloadBytes = 1024 * 1024 * 1024;
  static const int storageOverheadBytes = 256 * 1024 * 1024;
  static const int concurrentExecutions = 4;
  static const int readersPerExecution = 1;
  static const int readersPerClient = 8;
  static const int readersPerConnection = 16;
  static const int readersPerAgent = 32;
  static const writeTimeout = Duration(seconds: 10);
  static const drainTimeout = Duration(seconds: 5);
  static const pollTimeout = Duration(seconds: 20);
  static const requestTimeout = Duration(seconds: 30);
  static const responseReserve = Duration(seconds: 5);
  static const outputRetention = Duration(hours: 24);
  static const deduplicationRetention = Duration(days: 3);
  static const initialMessageId = 'system:initial';
  static const closeMessageId = 'system:close';
  static const reservedMessagePrefix = 'system:';
}

enum ActionIoDeliveryState { accepted, writing, written, failed, unknown }

enum ActionIoStdinState { pending, open, closing, closed, failed }

enum ActionIoCaptureState { capturing, draining, complete, incomplete, expired }

enum ActionIoStream { stdout, stderr }

final class ActionIoConfiguration {
  ActionIoConfiguration({required this.closeInput, List<int>? initialInput})
    : initialInput = initialInput == null ? null : Uint8List.fromList(initialInput).asUnmodifiableView();

  final bool closeInput;
  final Uint8List? initialInput;
}
