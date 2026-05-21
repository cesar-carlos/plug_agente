import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

abstract class IDeveloperData7ConnectionGateway {
  Future<Result<DeveloperData7ConnectionLookupResult>> listConnections(
    DeveloperData7ConnectionLookupRequest request,
  );
}
