import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol_capabilities.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';

void main() {
  group('RpcRequestSchemaValidator', () {
    const validator = RpcRequestSchemaValidator();

    group('validateSingle', () {
      test('should succeed for valid request', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {'sql': 'SELECT 1'},
        };

        final result = validator.validateSingle(data);

        check(result.isSuccess()).isTrue();
      });

      test('should succeed for notification (null id)', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': null,
          'params': {'sql': 'SELECT 1'},
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should fail when jsonrpc is not 2.0', () {
        final data = <String, dynamic>{
          'jsonrpc': '1.0',
          'method': 'sql.execute',
          'id': 'req-1',
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('2.0'));
      });

      test('should fail when method is missing', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'id': 'req-1',
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('method'));
      });

      test('should fail when method is not string', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 123,
          'id': 'req-1',
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('string'));
      });

      test('should fail when method is empty', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': '',
          'id': 'req-1',
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('empty'));
      });

      test('should fail when id is invalid type', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': <String>['invalid'],
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('id'));
      });

      test('should fail when traceparent is malformed', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {'sql': 'SELECT 1'},
          'meta': {
            'traceparent': 'invalid-traceparent',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
      });

      test('should fail when tracestate is malformed', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {'sql': 'SELECT 1'},
          'meta': {
            'tracestate': 'invalid tracestate without separator',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
      });

      test(
        'should fail with invalidParams for sql.execute schema violations',
        () {
          final data = <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'req-1',
            'params': {
              'sql': '',
              'unexpected': true,
            },
          };

          final result = validator.validateSingle(data);

          expect(result.isError(), isTrue);
          final err = result.exceptionOrNull()! as domain.ValidationFailure;
          expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
        },
      );

      test(
        'should fail when sql.executeBatch exceeds negotiated batch size',
        () {
          final data = <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.executeBatch',
            'id': 'req-1',
            'params': {
              'commands': List.generate(
                3,
                (index) => {'sql': 'SELECT $index'},
              ),
            },
          };

          final result = validator.validateSingle(
            data,
            limits: const TransportLimits(maxBatchSize: 2),
          );

          expect(result.isError(), isTrue);
          final err = result.exceptionOrNull()! as domain.ValidationFailure;
          expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
        },
      );

      test('should succeed for sql.executeBatch with execution_order', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.executeBatch',
          'id': 'req-1',
          'params': {
            'commands': [
              {'sql': 'SELECT 1', 'execution_order': 2},
              {'sql': 'SELECT 2', 'execution_order': 1},
              {'sql': 'SELECT 3'},
            ],
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should fail when sql.executeBatch execution_order is invalid', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.executeBatch',
          'id': 'req-1',
          'params': {
            'commands': [
              {'sql': 'SELECT 1', 'execution_order': -1},
            ],
          },
        };

        final result = validator.validateSingle(data);

        check(result.isError()).isTrue();
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        check(err.context['rpc_error_code']).equals(RpcErrorCode.invalidParams);
        check(err.message).contains('execution_order');
      });

      test('should fail when sql.cancel omits execution identifiers', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.cancel',
          'id': 'req-1',
          'params': <String, dynamic>{},
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should accept agent.getProfile params with client token alias', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'agent.getProfile',
          'id': 'req-1',
          'params': {
            'client_token': 'token-abc',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should accept agent.getProfile include_diagnostics flag', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'agent.getProfile',
          'id': 'req-1',
          'params': {
            'include_diagnostics': true,
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should reject unsupported agent.getProfile params', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'agent.getProfile',
          'id': 'req-1',
          'params': {
            'unexpected': true,
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should accept agent.getHealth params with client token alias', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'agent.getHealth',
          'id': 'req-1',
          'params': {
            'auth': 'token-abc',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should reject unsupported agent.getHealth params', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'agent.getHealth',
          'id': 'req-1',
          'params': {
            'extra': 1,
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should accept agent.action.getExecution params with token alias', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          'id': 'req-1',
          'params': {
            'execution_id': 'execution-1',
            'auth': 'token-abc',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should accept agent.action.getExecution params with output paging fields', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          'id': 'req-1',
          'params': {
            'execution_id': 'execution-1',
            'include_output': true,
            'stdout_offset': 0,
            'stdout_cursor': 0,
            'output_offset': 0,
            'stderr_offset': 10,
            'stderr_cursor': 10,
            'max_output_bytes': 4096,
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should reject agent.action.getExecution when max_output_bytes is zero', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          'id': 'req-1',
          'params': {
            'execution_id': 'execution-1',
            'max_output_bytes': 0,
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
      });

      test('should reject agent.action.getExecution when max_output_bytes exceeds cap', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          'id': 'req-1',
          'params': {
            'execution_id': 'execution-1',
            'max_output_bytes': 600000,
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
      });

      test('should reject agent.action.getExecution without execution id', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          'id': 'req-1',
          'params': {
            'auth': 'token-abc',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should accept agent.action.run params with optional trace_id and requested_by', () {
        final result = validator.validateSingle(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionRunRpcMethodName,
          'id': 1,
          'params': <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-1',
            'trace_id': 'trace-1',
            'requested_by': 'hub-user',
          },
        });
        expect(result.isSuccess(), isTrue);
      });

      test('should accept agent.action.run params with idempotency key and token alias', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionRunRpcMethodName,
          'id': 'req-1',
          'params': {
            'action_id': 'action-1',
            'idempotency_key': 'remote-key-1',
            'clientToken': 'token-abc',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should reject agent.action.run ad-hoc params', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionRunRpcMethodName,
          'id': 'req-1',
          'params': {
            'action_id': 'action-1',
            'idempotency_key': 'remote-key-1',
            'command': 'dir',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should reject agent.action.run context param with remote_context_not_supported reason', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionRunRpcMethodName,
          'id': 'req-1',
          'params': {
            'action_id': 'action-1',
            'idempotency_key': 'remote-key-1',
            'context_json': <String, dynamic>{'key': 'value'},
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as ActionValidationFailure;
        expect(err.code, AgentActionFailureCode.remoteContextNotSupported);
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
        expect(err.context['reason'], AgentActionRpcConstants.remoteContextNotSupportedRpcReason);
        expect(err.context['field'], 'context_json');
      });

      test('should reject agent.action.run without idempotency key', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionRunRpcMethodName,
          'id': 'req-1',
          'params': {
            'action_id': 'action-1',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should accept agent.action.validateRun params with idempotency key and token alias', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
          'id': 'req-1',
          'params': {
            'action_id': 'action-1',
            'idempotency_key': 'remote-key-validate-1',
            'clientToken': 'token-abc',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should reject agent.action.validateRun ad-hoc params', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
          'id': 'req-1',
          'params': {
            'action_id': 'action-1',
            'idempotency_key': 'remote-key-validate-1',
            'command': 'dir',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should reject agent.action.validateRun without idempotency key', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
          'id': 'req-1',
          'params': {
            'action_id': 'action-1',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should accept agent.action.cancel params with token alias', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionCancelRpcMethodName,
          'id': 'req-1',
          'params': {
            'execution_id': 'execution-1',
            'auth': 'token-abc',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should reject agent.action.cancel without execution id', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionCancelRpcMethodName,
          'id': 'req-1',
          'params': {
            'auth': 'token-abc',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should accept client_token.getPolicy params with client token alias', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'client_token.getPolicy',
          'id': 'req-1',
          'params': {
            'auth': 'token-abc',
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should reject unsupported client_token.getPolicy params', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'client_token.getPolicy',
          'id': 'req-1',
          'params': {
            'extra': 1,
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should succeed when id is number', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 1,
          'params': {'sql': 'SELECT 1'},
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should succeed for sql.execute pagination options', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT 1',
            'options': {'page': 2, 'page_size': 100},
          },
        };

        final result = validator.validateSingle(
          data,
          limits: const TransportLimits(maxRows: 200),
        );

        expect(result.isSuccess(), isTrue);
      });

      test('should fail when page_size exceeds negotiated max_rows', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT 1',
            'options': {'page': 1, 'page_size': 500},
          },
        };

        final result = validator.validateSingle(
          data,
          limits: const TransportLimits(maxRows: 100),
        );

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull()! as domain.ValidationFailure;
        expect(err.context['rpc_error_code'], RpcErrorCode.invalidParams);
      });

      test('should succeed for sql.execute cursor pagination option', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT 1',
            'options': {'cursor': 'opaque-token'},
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should succeed for sql.execute multi_result option', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT 1; SELECT 2;',
            'options': {'multi_result': true},
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should succeed for sql.execute prefer_db_streaming option', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT * FROM users',
            'options': {'prefer_db_streaming': true},
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should succeed for sql.execute execution_mode preserve option', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT * FROM users LIMIT 10',
            'options': {'execution_mode': 'preserve'},
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should succeed for deprecated preserve_sql alias', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT * FROM users LIMIT 10',
            'options': {'preserve_sql': true},
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isSuccess(), isTrue);
      });

      test(
        'should fail when multi_result is combined with pagination options',
        () {
          final data = <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'req-1',
            'params': {
              'sql': 'SELECT 1; SELECT 2;',
              'options': {
                'multi_result': true,
                'page': 1,
                'page_size': 100,
              },
            },
          };

          final result = validator.validateSingle(data);

          expect(result.isError(), isTrue);
        },
      );

      test(
        'should fail when multi_result is combined with named parameters',
        () {
          final data = <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'req-1',
            'params': {
              'sql': 'SELECT * FROM users WHERE id = :id; SELECT 2;',
              'params': {'id': 1},
              'options': {'multi_result': true},
            },
          };

          final result = validator.validateSingle(data);

          expect(result.isError(), isTrue);
        },
      );

      test('should fail when cursor is combined with page options', () {
        final data = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-1',
          'params': {
            'sql': 'SELECT 1',
            'options': {
              'cursor': 'opaque-token',
              'page': 1,
              'page_size': 100,
            },
          },
        };

        final result = validator.validateSingle(data);

        expect(result.isError(), isTrue);
      });

      test(
        'should fail when execution_mode preserve is combined with pagination options',
        () {
          final data = <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'req-1',
            'params': {
              'sql': 'SELECT * FROM users',
              'options': {
                'execution_mode': 'preserve',
                'page': 1,
                'page_size': 100,
              },
            },
          };

          final result = validator.validateSingle(data);

          expect(result.isError(), isTrue);
        },
      );

      test(
        'should fail when preserve_sql conflicts with execution_mode managed',
        () {
          final data = <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'req-1',
            'params': {
              'sql': 'SELECT * FROM users',
              'options': {
                'preserve_sql': true,
                'execution_mode': 'managed',
              },
            },
          };

          final result = validator.validateSingle(data);

          expect(result.isError(), isTrue);
        },
      );
    });

    group('validateBatch', () {
      test('should succeed for valid batch', () {
        final data = [
          <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'r-1',
            'params': {'sql': 'SELECT 1'},
          },
          <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'r-2',
            'params': {'sql': 'SELECT 2'},
          },
        ];

        final result = validator.validateBatch(data);

        expect(result.isSuccess(), isTrue);
      });

      test('should fail when batch item is not object', () {
        final data = [
          <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'r-1',
            'params': {'sql': 'SELECT 1'},
          },
          'invalid',
        ];

        final result = validator.validateBatch(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('index 1'));
      });

      test('should fail when batch item fails single validation', () {
        final data = [
          <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'r-1',
            'params': {'sql': 'SELECT 1'},
          },
          <String, dynamic>{
            'jsonrpc': '2.0',
            'method': '',
            'id': 'r-2',
          },
        ];

        final result = validator.validateBatch(data);

        expect(result.isError(), isTrue);
        final err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect((err! as domain.ValidationFailure).message, contains('index 1'));
      });

      test('should fail when batch exceeds negotiated limit', () {
        final data = List.generate(
          3,
          (index) => <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': 'r-$index',
            'params': {'sql': 'SELECT $index'},
          },
        );

        final result = validator.validateBatch(
          data,
          limits: const TransportLimits(maxBatchSize: 2),
        );

        expect(result.isError(), isTrue);
      });
    });
  });
}
