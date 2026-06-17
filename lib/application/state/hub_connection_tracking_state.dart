/// Mutable hub connection tracking state shared between coordination and presentation.
final class HubConnectionTrackingState {
  String? lastConfigId;
  String? lastServerUrl;
  String? lastAgentId;
  String? lastAuthToken;
  bool sessionAuthInvalid = false;
}
