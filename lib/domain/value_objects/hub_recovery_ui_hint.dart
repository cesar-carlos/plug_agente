/// Finer-grained UI label while the hub link is in a reconnecting state.
enum HubRecoveryUiHint {
  none,
  signingIn,
  connectingSocket,
  awaitingHubReachability,
  negotiationTimedOut,
}
