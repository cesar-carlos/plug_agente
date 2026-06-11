import 'package:plug_agente/core/config/app_environment.dart';

/// Persistence policy for captured process stdout/stderr.
abstract final class AgentActionCapturedOutputConstants {
  /// Stream values stored in the `agent_action_captured_output_chunk.stream` column.
  static const String stdoutStream = 'stdout';
  static const String stderrStream = 'stderr';

  /// Max UTF-8 bytes kept inline on the execution row; larger payloads spill to chunks.
  static const int defaultInlineMaxUtf8Bytes = 16 * 1024;

  /// Max UTF-8 bytes per Drift chunk row.
  static const int defaultChunkPayloadUtf8Bytes = 32 * 1024;

  static int get inlineMaxUtf8Bytes => _positiveInt(
    'AGENT_ACTION_CAPTURED_OUTPUT_INLINE_MAX_BYTES',
    defaultInlineMaxUtf8Bytes,
    min: 1024,
    max: 256 * 1024,
  );

  static int get chunkPayloadUtf8Bytes => _positiveInt(
    'AGENT_ACTION_CAPTURED_OUTPUT_CHUNK_BYTES',
    defaultChunkPayloadUtf8Bytes,
    min: 4096,
    max: 512 * 1024,
  );

  static int _positiveInt(
    String envKey,
    int fallback, {
    required int min,
    required int max,
  }) {
    final parsed = int.tryParse(AppEnvironment.get(envKey) ?? '');
    final value = (parsed == null || parsed <= 0) ? fallback : parsed;
    return value.clamp(min, max);
  }
}
