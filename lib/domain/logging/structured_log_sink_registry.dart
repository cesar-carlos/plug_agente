import 'package:plug_agente/domain/logging/i_structured_log_sink.dart';

class StructuredLogSinkRegistry {
  StructuredLogSinkRegistry._();

  static IStructuredLogSink? instance;

  static void register(IStructuredLogSink? sink) {
    instance = sink;
  }

  static void reset() {
    instance = null;
  }
}
