import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_developer_data7_connection_gateway.dart';
import 'package:result_dart/result_dart.dart';

class ListDeveloperData7Connections {
  const ListDeveloperData7Connections(this._gateway);

  final IDeveloperData7ConnectionGateway _gateway;

  Future<Result<DeveloperData7ConnectionLookupResult>> call(
    DeveloperData7ConnectionLookupRequest request,
  ) async {
    final actionId = request.actionId.trim();
    if (actionId.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action id is required to list Developer Data7 connections.',
          context: const {
            'field': 'actionId',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe uma acao valida antes de carregar as conexoes Data7.',
          },
        ),
      );
    }

    return _gateway.listConnections(request);
  }
}
