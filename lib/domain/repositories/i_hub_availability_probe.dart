abstract interface class IHubAvailabilityProbe {
  Future<bool> isServerReachable(String serverUrl);
}
