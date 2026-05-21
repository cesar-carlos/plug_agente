import 'package:plug_agente/core/config/app_environment.dart';

/// Deployment-wide defaults and ceilings for agent action policies.
///
/// Per-definition values in Drift must stay at or below these caps when saved.
/// Socket.IO capabilities advertise the same limits to the hub.
abstract final class AgentActionPolicyDefaults {
  static const int defaultMaxConcurrentActions = 1;
  static const int defaultMaxQueuedActions = 100;
  static const int defaultQueueTimeoutSeconds = 300;
  static const int defaultMaxRuntimeSeconds = 1800;
  static const int defaultMaxRetryAttempts = 1;
  static const int defaultMaxContextBytes = 256 * 1024;
  static const int defaultMaxCapturedOutputBytes = 64 * 1024;

  /// Max `agent.action.getExecution` / `agent.action.validateRun` items per JSON-RPC batch.
  static const int defaultMaxAgentActionReadRpcMethodsPerBatch = 32;

  static int get maxConcurrentActions => _positiveInt(
    'AGENT_ACTION_MAX_CONCURRENT',
    defaultMaxConcurrentActions,
    min: 1,
    max: 64,
  );

  static int get maxQueuedActions => _positiveInt(
    'AGENT_ACTION_MAX_QUEUED',
    defaultMaxQueuedActions,
    min: 0,
    max: 10000,
  );

  static Duration get defaultQueueTimeout => Duration(
    seconds: _positiveInt(
      'AGENT_ACTION_QUEUE_TIMEOUT_SECONDS',
      defaultQueueTimeoutSeconds,
      min: 1,
      max: 86400,
    ),
  );

  static Duration get defaultMaxRuntime => Duration(
    seconds: _positiveInt(
      'AGENT_ACTION_MAX_RUNTIME_SECONDS',
      defaultMaxRuntimeSeconds,
      min: 1,
      max: 86400,
    ),
  );

  static int get maxRetryAttempts => _positiveInt(
    'AGENT_ACTION_MAX_RETRIES',
    defaultMaxRetryAttempts,
    min: 1,
    max: 32,
  );

  static int get maxContextBytes => _positiveInt(
    'AGENT_ACTION_MAX_CONTEXT_BYTES',
    defaultMaxContextBytes,
    min: 1024,
    max: 16 * 1024 * 1024,
  );

  static int get maxCapturedOutputBytes => _positiveInt(
    'AGENT_ACTION_MAX_CAPTURED_OUTPUT_BYTES',
    defaultMaxCapturedOutputBytes,
    min: 1024,
    max: 16 * 1024 * 1024,
  );

  static int get maxAgentActionReadRpcMethodsPerBatch => _positiveInt(
    'AGENT_ACTION_MAX_READ_RPC_PER_BATCH',
    defaultMaxAgentActionReadRpcMethodsPerBatch,
    min: 1,
    max: 256,
  );

  static int get defaultQueueTimeoutMs => defaultQueueTimeout.inMilliseconds;

  static Map<String, Object?> get defaultQueueLimitsCapability => <String, Object?>{
    'maxConcurrent': maxConcurrentActions,
    'maxQueued': maxQueuedActions,
    'queueTimeoutMs': defaultQueueTimeoutMs,
  };

  static Map<String, Object?> limitsCapability({
    required int defaultMaxOutputBytesPerStream,
    required int maxMaxOutputBytesPerStream,
  }) {
    return <String, Object?>{
      'maxConcurrentActions': maxConcurrentActions,
      'maxQueuedActions': maxQueuedActions,
      'maxContextBytes': maxContextBytes,
      'defaultMaxRuntimeSeconds': defaultMaxRuntime.inSeconds,
      'defaultMaxRetryAttempts': maxRetryAttempts,
      'defaultMaxCapturedOutputBytes': maxCapturedOutputBytes,
      'defaultMaxOutputBytesPerStream': defaultMaxOutputBytesPerStream,
      'maxMaxOutputBytesPerStream': maxMaxOutputBytesPerStream,
      'supportsOutputPaging': true,
      'maxReadMethodsPerBatch': maxAgentActionReadRpcMethodsPerBatch,
    };
  }

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
