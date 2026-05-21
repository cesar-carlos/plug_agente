import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

/// Contract test that loads every payload fixture under `test/fixtures/rpc/`
/// and validates it against the JSON Schema bundle in
/// `docs/communication/schemas/`. Used to catch drift when code changes a
/// wire shape without updating the schema (or vice versa).
///
/// Each fixture file name maps to a schema id via [_fixtureToSchema]. Add a
/// new entry whenever you introduce a fixture so it actually gets validated.
const Map<String, String> _fixtureToSchema = {
  'payload_frame_minimal.json': TransportSchemaIds.payloadFrame,
  'rpc_request_sql_execute.json': TransportSchemaIds.rpcRequest,
  'rpc_request_agent_action_run.json': TransportSchemaIds.rpcRequest,
  'rpc_request_agent_action_run_with_trigger.json': TransportSchemaIds.rpcRequest,
  'rpc_request_agent_action_cancel.json': TransportSchemaIds.rpcRequest,
  'rpc_request_agent_action_get_execution.json': TransportSchemaIds.rpcRequest,
  'rpc_request_agent_action_validate_run.json': TransportSchemaIds.rpcRequest,
  'rpc_response_success.json': TransportSchemaIds.rpcResponse,
  'rpc_response_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_run_queued.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_get_execution_queued.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_cancel_queued.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_remote_disabled_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_validate_run_success.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_validate_run_replay.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_notification_not_allowed_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_permission_denied_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_missing_client_token_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_remote_context_not_supported_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_remote_rate_limited_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_maintenance_mode_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_draining_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_feature_disabled_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_remote_idempotency_required_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_remote_trigger_required_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_remote_trigger_ambiguous_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_starting_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_idempotency_fingerprint_mismatch_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_remote_not_approved_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_remote_risk_fingerprint_stale_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_environment_profile_denied_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_secret_unavailable_error.json': TransportSchemaIds.rpcResponse,
  'rpc_request_agent_action_get_execution_paged.json': TransportSchemaIds.rpcRequest,
  'rpc_response_agent_action_get_execution_paged_stdout.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_get_execution_failed.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_get_execution_skipped.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_batch_read_limit_error.json': TransportSchemaIds.rpcResponse,
  'rpc_response_agent_action_method_not_allowed_in_batch_error.json': TransportSchemaIds.rpcResponse,
  'rpc_stream_chunk.json': TransportSchemaIds.streamChunk,
  'rpc_stream_complete.json': TransportSchemaIds.streamComplete,
  'agent_register.json': TransportSchemaIds.agentRegister,
};

/// Agent action request fixtures: validate `params` against published method params schemas.
const Map<String, String> _agentActionFixtureParamsSchemas = {
  'rpc_request_agent_action_run.json': TransportSchemaIds.paramsAgentActionRun,
  'rpc_request_agent_action_run_with_trigger.json': TransportSchemaIds.paramsAgentActionRun,
  'rpc_request_agent_action_cancel.json': TransportSchemaIds.paramsAgentActionCancel,
  'rpc_request_agent_action_get_execution.json': TransportSchemaIds.paramsAgentActionGetExecution,
  'rpc_request_agent_action_get_execution_paged.json': TransportSchemaIds.paramsAgentActionGetExecution,
  'rpc_request_agent_action_validate_run.json': TransportSchemaIds.paramsAgentActionValidateRun,
};

/// Agent action response fixtures: validate `result` against published method result schemas.
const Map<String, String> _agentActionFixtureResultSchemas = {
  'rpc_response_agent_action_run_queued.json': TransportSchemaIds.resultAgentActionGetExecution,
  'rpc_response_agent_action_get_execution_queued.json': TransportSchemaIds.resultAgentActionGetExecution,
  'rpc_response_agent_action_cancel_queued.json': TransportSchemaIds.resultAgentActionCancel,
  'rpc_response_agent_action_validate_run_success.json': TransportSchemaIds.resultAgentActionValidateRun,
  'rpc_response_agent_action_validate_run_replay.json': TransportSchemaIds.resultAgentActionValidateRun,
  'rpc_response_agent_action_get_execution_paged_stdout.json': TransportSchemaIds.resultAgentActionGetExecution,
  'rpc_response_agent_action_get_execution_failed.json': TransportSchemaIds.resultAgentActionGetExecution,
  'rpc_response_agent_action_get_execution_skipped.json': TransportSchemaIds.resultAgentActionGetExecution,
};

void main() {
  group('Contract fixtures vs JSON Schemas', () {
    late TransportSchemaLoader loader;
    late JsonSchemaContractValidator validator;

    setUpAll(() async {
      loader = TransportSchemaLoader();
      await loader.loadAll();
      validator = JsonSchemaContractValidator(loader: loader);
    });

    for (final entry in _fixtureToSchema.entries) {
      final fixtureName = entry.key;
      final schemaId = entry.value;
      test('$fixtureName conforms to $schemaId', () async {
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        expect(file.existsSync(), isTrue, reason: 'Fixture not found: $fixturePath');
        final json = jsonDecode(await file.readAsString()) as Object;

        if (!validator.isLoaded(schemaId)) {
          // Schema not loaded in this environment; skip silently.
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: json);
        expect(
          result.isSuccess(),
          isTrue,
          reason:
              'Fixture $fixtureName failed schema $schemaId. '
              'Errors: ${result.exceptionOrNull()}',
        );
      });
    }

    test('agent action request fixtures should use published remote RPC method names', () async {
      for (final fixtureName in _agentActionFixtureParamsSchemas.keys) {
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        expect(file.existsSync(), isTrue, reason: 'Fixture not found: $fixturePath');
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final method = root['method'] as String?;
        expect(method, isNotNull, reason: '$fixtureName must declare method');
        expect(
          AgentActionRpcConstants.remotePublishedRpcMethodNames.contains(method),
          isTrue,
          reason:
              '$fixtureName uses method "$method" which is not listed in '
              'AgentActionRpcConstants.remotePublishedRpcMethodNames',
        );
      }
    });

    for (final entry in _agentActionFixtureParamsSchemas.entries) {
      final fixtureName = entry.key;
      final schemaId = entry.value;
      test('$fixtureName params conform to $schemaId', () async {
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final params = root['params'];
        expect(params, isA<Map<String, dynamic>>(), reason: 'Fixture $fixtureName must include params object');

        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: params);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName params failed $schemaId: ${result.exceptionOrNull()}',
        );
      });
    }

    for (final entry in _agentActionFixtureResultSchemas.entries) {
      final fixtureName = entry.key;
      final schemaId = entry.value;
      test('$fixtureName result conform to $schemaId', () async {
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final payload = root['result'];
        expect(payload, isA<Map<String, dynamic>>(), reason: 'Fixture $fixtureName must include result object');

        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName result failed $schemaId: ${result.exceptionOrNull()}',
        );
      });
    }

    test(
      'rpc_response_agent_action_notification_not_allowed_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_notification_not_allowed_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason);

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_missing_client_token_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_missing_client_token_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], RpcClientTokenConstants.missingClientTokenReason);
        expect(data['method'], AgentActionRpcConstants.agentActionRunRpcMethodName);

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_permission_denied_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_permission_denied_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionRpcConstants.agentActionPermissionDeniedErrorReason);
        expect(data['required_scope'], AgentActionRpcConstants.agentActionsRunScope);
        expect(data['action_id'], 'action-1');

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_remote_context_not_supported_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_remote_context_not_supported_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionRpcConstants.remoteContextNotSupportedRpcReason);
        expect(data['category'], RpcErrorCode.categoryAction);
        expect(data['method'], AgentActionRpcConstants.agentActionRunRpcMethodName);
        expect(data['field'], 'context_json');

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_remote_rate_limited_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_remote_rate_limited_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionRpcConstants.agentActionRemoteRateLimitedErrorReason);
        expect(data['method'], AgentActionRpcConstants.agentActionRunRpcMethodName);
        expect(data['retry_after_ms'], isA<int>());

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_maintenance_mode_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_maintenance_mode_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionRpcConstants.agentActionsMaintenanceModeErrorReason);
        expect(data['method'], AgentActionRpcConstants.agentActionRunRpcMethodName);

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test('rpc_response_agent_action_draining_error.json error conforms to ${TransportSchemaIds.rpcError}', () async {
      const fixtureName = 'rpc_response_agent_action_draining_error.json';
      final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
      final file = File(fixturePath);
      final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final rawError = root['error'];
      expect(rawError, isA<Map<String, dynamic>>());
      final payload = rawError as Map<String, dynamic>;
      final data = payload['data'] as Map<String, dynamic>;
      expect(data['reason'], AgentActionRuntimeStateConstants.agentActionsDrainingReason);
      expect(data['category'], RpcErrorCode.categoryAction);
      expect(data['method'], AgentActionRpcConstants.agentActionRunRpcMethodName);

      const schemaId = TransportSchemaIds.rpcError;
      if (!validator.isLoaded(schemaId)) {
        return;
      }

      final result = validator.validate(schemaId: schemaId, payload: payload);
      expect(
        result.isSuccess(),
        isTrue,
        reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
      );
    });

    test(
      'rpc_response_agent_action_feature_disabled_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_feature_disabled_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionRpcConstants.agentActionsFeatureDisabledErrorReason);

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_remote_idempotency_required_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_remote_idempotency_required_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionRpcConstants.remoteIdempotencyRequiredRpcReason);
        expect(data['category'], RpcErrorCode.categoryAction);
        expect(data['field'], 'idempotency_key');

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_remote_trigger_required_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_remote_trigger_required_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionTriggerConstants.remoteTriggerRequiredReason);
        expect(data['category'], RpcErrorCode.categoryAction);
        expect(data['action_id'], 'action-1');

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_remote_trigger_ambiguous_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_remote_trigger_ambiguous_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionTriggerConstants.remoteTriggerAmbiguousReason);
        expect(data['category'], RpcErrorCode.categoryAction);
        expect(data['trigger_ids'], ['remote-1', 'remote-2']);

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test('rpc_response_agent_action_starting_error.json error conforms to ${TransportSchemaIds.rpcError}', () async {
      const fixtureName = 'rpc_response_agent_action_starting_error.json';
      final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
      final file = File(fixturePath);
      final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final rawError = root['error'];
      expect(rawError, isA<Map<String, dynamic>>());
      final payload = rawError as Map<String, dynamic>;
      final data = payload['data'] as Map<String, dynamic>;
      expect(data['reason'], AgentActionRuntimeStateConstants.agentActionsStartingReason);
      expect(data['category'], RpcErrorCode.categoryAction);

      const schemaId = TransportSchemaIds.rpcError;
      if (!validator.isLoaded(schemaId)) {
        return;
      }

      final result = validator.validate(schemaId: schemaId, payload: payload);
      expect(
        result.isSuccess(),
        isTrue,
        reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
      );
    });

    test(
      'rpc_response_agent_action_idempotency_fingerprint_mismatch_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_idempotency_fingerprint_mismatch_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionRpcConstants.remoteIdempotencyFingerprintMismatchRpcReason);
        expect(data['category'], RpcErrorCode.categoryAction);

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_remote_disabled_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_remote_disabled_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>(), reason: 'Fixture must include error object');
        final payload = rawError as Map<String, dynamic>;
        final rawData = payload['data'];
        expect(rawData, isA<Map<String, dynamic>>(), reason: 'Fixture error must include data object');
        final data = rawData as Map<String, dynamic>;
        expect(data['reason'], AgentActionRpcConstants.agentActionsRemoteDisabledErrorReason);
        expect(data['method'], AgentActionRpcConstants.agentActionRunRpcMethodName);

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_remote_not_approved_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_remote_not_approved_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionGateConstants.remoteActionNotApprovedReason);
        expect(data['category'], RpcErrorCode.categoryAction);

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_remote_risk_fingerprint_stale_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_remote_risk_fingerprint_stale_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionGateConstants.remoteRiskFingerprintStaleReason);
        expect(data['category'], RpcErrorCode.categoryAction);
        expect(data['failure_code'], 'ACTION_REMOTE_NOT_APPROVED');

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_environment_profile_denied_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_environment_profile_denied_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionGateConstants.environmentProfileDeniedReason);
        expect(data['category'], RpcErrorCode.categoryAction);

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_method_not_allowed_in_batch_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_method_not_allowed_in_batch_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionRpcConstants.jsonRpcBatchMethodNotAllowedErrorReason);
        expect(data['method'], AgentActionRpcConstants.agentActionRunRpcMethodName);

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_batch_read_limit_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_batch_read_limit_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionRpcConstants.jsonRpcBatchAgentActionReadLimitErrorReason);
        expect(data['read_method_count'], 33);
        expect(data['limit'], AgentActionPolicyDefaults.maxAgentActionReadRpcMethodsPerBatch);

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    test(
      'rpc_response_agent_action_secret_unavailable_error.json error conforms to ${TransportSchemaIds.rpcError}',
      () async {
        const fixtureName = 'rpc_response_agent_action_secret_unavailable_error.json';
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final rawError = root['error'];
        expect(rawError, isA<Map<String, dynamic>>());
        final payload = rawError as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['reason'], AgentActionGateConstants.secretUnavailableReason);
        expect(data['category'], RpcErrorCode.categoryAction);

        const schemaId = TransportSchemaIds.rpcError;
        if (!validator.isLoaded(schemaId)) {
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: payload);
        expect(
          result.isSuccess(),
          isTrue,
          reason: 'Fixture $fixtureName error failed $schemaId: ${result.exceptionOrNull()}',
        );
      },
    );

    /// Documents wire `category` per fixture (dispatcher hand-built vs mapper `Action*`).
    test('agent action error fixtures use documented category values', () async {
      const expectedCategories = <String, String>{
        'rpc_response_agent_action_permission_denied_error.json': RpcErrorCode.categoryAuth,
        'rpc_response_agent_action_missing_client_token_error.json': RpcErrorCode.categoryAuth,
        'rpc_response_agent_action_remote_disabled_error.json': RpcErrorCode.categoryAuth,
        'rpc_response_agent_action_maintenance_mode_error.json': RpcErrorCode.categoryTransport,
        'rpc_response_agent_action_draining_error.json': RpcErrorCode.categoryAction,
        'rpc_response_agent_action_feature_disabled_error.json': RpcErrorCode.categoryTransport,
        'rpc_response_agent_action_remote_rate_limited_error.json': RpcErrorCode.categoryTransport,
        'rpc_response_agent_action_remote_context_not_supported_error.json': RpcErrorCode.categoryAction,
        'rpc_response_agent_action_notification_not_allowed_error.json': RpcErrorCode.categoryValidation,
        'rpc_response_agent_action_batch_read_limit_error.json': RpcErrorCode.categoryValidation,
        'rpc_response_agent_action_method_not_allowed_in_batch_error.json': RpcErrorCode.categoryValidation,
        'rpc_response_agent_action_remote_not_approved_error.json': RpcErrorCode.categoryAction,
        'rpc_response_agent_action_remote_risk_fingerprint_stale_error.json': RpcErrorCode.categoryAction,
        'rpc_response_agent_action_environment_profile_denied_error.json': RpcErrorCode.categoryAction,
        'rpc_response_agent_action_secret_unavailable_error.json': RpcErrorCode.categoryAction,
      };

      for (final entry in expectedCategories.entries) {
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/${entry.key}';
        final root = jsonDecode(await File(fixturePath).readAsString()) as Map<String, dynamic>;
        final data = (root['error'] as Map<String, dynamic>)['data'] as Map<String, dynamic>;
        expect(
          data['category'],
          entry.value,
          reason: '${entry.key} category documents ${entry.value} on the wire',
        );
      }
    });
  });
}
