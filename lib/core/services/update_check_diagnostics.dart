class UpdateCheckDiagnostics {
  const UpdateCheckDiagnostics({
    required this.checkedAt,
    required this.configuredFeedUrl,
    required this.requestedFeedUrl,
    this.appcastProbeVersion,
    this.appcastProbeItemCount,
    this.updateAvailable,
    this.remoteVersion,
    this.remoteDisplayVersion,
    this.errorMessage,
    this.probeErrorMessage,
  });

  final DateTime checkedAt;
  final String configuredFeedUrl;
  final String requestedFeedUrl;
  final String? appcastProbeVersion;
  final int? appcastProbeItemCount;
  final bool? updateAvailable;
  final String? remoteVersion;
  final String? remoteDisplayVersion;
  final String? errorMessage;
  final String? probeErrorMessage;

  UpdateCheckDiagnostics copyWith({
    DateTime? checkedAt,
    String? configuredFeedUrl,
    String? requestedFeedUrl,
    String? appcastProbeVersion,
    int? appcastProbeItemCount,
    bool? updateAvailable,
    String? remoteVersion,
    String? remoteDisplayVersion,
    String? errorMessage,
    String? probeErrorMessage,
  }) {
    return UpdateCheckDiagnostics(
      checkedAt: checkedAt ?? this.checkedAt,
      configuredFeedUrl: configuredFeedUrl ?? this.configuredFeedUrl,
      requestedFeedUrl: requestedFeedUrl ?? this.requestedFeedUrl,
      appcastProbeVersion: appcastProbeVersion ?? this.appcastProbeVersion,
      appcastProbeItemCount:
          appcastProbeItemCount ?? this.appcastProbeItemCount,
      updateAvailable: updateAvailable ?? this.updateAvailable,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      remoteDisplayVersion: remoteDisplayVersion ?? this.remoteDisplayVersion,
      errorMessage: errorMessage ?? this.errorMessage,
      probeErrorMessage: probeErrorMessage ?? this.probeErrorMessage,
    );
  }
}
