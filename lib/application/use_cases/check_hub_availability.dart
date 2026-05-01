import 'package:plug_agente/domain/repositories/i_hub_availability_probe.dart';

class CheckHubAvailability {
  CheckHubAvailability(this._probe);

  final IHubAvailabilityProbe _probe;

  Future<bool> call(String serverUrl) => _probe.isServerReachable(serverUrl);
}
