import 'package:plug_agente/core/constants/agent_action_com_object_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_handler.dart';
import 'package:result_dart/result_dart.dart';

class ComObjectInvocationRegistry {
  ComObjectInvocationRegistry(Iterable<RegisteredComObjectInvocation> registrations)
    : _handlers = _buildHandlers(registrations);

  final Map<ComObjectInvocationKey, ComObjectInvocationHandler> _handlers;

  Set<ComObjectInvocationKey> get registeredInvocations => Set<ComObjectInvocationKey>.unmodifiable(_handlers.keys);

  bool isRegistered({
    required String progId,
    required String memberName,
  }) {
    return _handlers.containsKey(
      (
        progId: _normalizeProgId(progId),
        memberName: _normalizeMemberName(memberName),
      ),
    );
  }

  Result<ComObjectInvocationHandler> resolve({
    required String progId,
    required String memberName,
  }) {
    final handler =
        _handlers[(
          progId: _normalizeProgId(progId),
          memberName: _normalizeMemberName(memberName),
        )];
    if (handler == null) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'COM object invocation is not registered for this agent.',
          context: {
            'prog_id': progId,
            'member_name': memberName,
            'phase': AgentActionProcessConstants.executionPreflightPhase,
            'reason': AgentActionComObjectConstants.invocationNotRegisteredReason,
            'user_message': 'Esta combinacao de ProgID e membro COM nao esta habilitada neste agente.',
          },
        ),
      );
    }

    return Success(handler);
  }

  static Map<ComObjectInvocationKey, ComObjectInvocationHandler> _buildHandlers(
    Iterable<RegisteredComObjectInvocation> registrations,
  ) {
    final handlers = <ComObjectInvocationKey, ComObjectInvocationHandler>{};
    for (final registration in registrations) {
      final key = (
        progId: _normalizeProgId(registration.progId),
        memberName: _normalizeMemberName(registration.memberName),
      );
      final existing = handlers[key];
      if (existing != null) {
        throw StateError(
          'Duplicate COM object invocation for "${registration.progId}.${registration.memberName}": '
          '${existing.runtimeType} and ${registration.handler.runtimeType}.',
        );
      }
      handlers[key] = registration.handler;
    }

    return Map<ComObjectInvocationKey, ComObjectInvocationHandler>.unmodifiable(handlers);
  }

  static String _normalizeProgId(String value) => value.trim();

  static String _normalizeMemberName(String value) => value.trim();
}

class RegisteredComObjectInvocation {
  const RegisteredComObjectInvocation({
    required this.progId,
    required this.memberName,
    required this.handler,
  });

  final String progId;
  final String memberName;
  final ComObjectInvocationHandler handler;
}
