enum UpdateCheckCompletionSource {
  updateAvailable,
  updateNotAvailable,
  updaterError,
  triggerTimeout,
  completionTimeout,
  triggerFailure,
  notInitialized,
  circuitOpen,
}

class UpdateCheckDiagnostics {
  const UpdateCheckDiagnostics({
    required this.checkedAt,
    required this.configuredFeedUrl,
    required this.requestedFeedUrl,
    this.currentVersion,
    this.probeRequestUrl,
    this.triggerStartedAt,
    this.triggerCompletedAt,
    this.completedAt,
    this.completionSource,
    this.probeSucceeded,
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
  final String? currentVersion;
  final String? probeRequestUrl;
  final DateTime? triggerStartedAt;
  final DateTime? triggerCompletedAt;
  final DateTime? completedAt;
  final UpdateCheckCompletionSource? completionSource;
  final bool? probeSucceeded;
  final String? appcastProbeVersion;
  final int? appcastProbeItemCount;
  final bool? updateAvailable;
  final String? remoteVersion;
  final String? remoteDisplayVersion;
  final String? errorMessage;
  final String? probeErrorMessage;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'checkedAt': checkedAt.toIso8601String(),
      'configuredFeedUrl': configuredFeedUrl,
      'requestedFeedUrl': requestedFeedUrl,
      'currentVersion': currentVersion,
      'probeRequestUrl': probeRequestUrl,
      'triggerStartedAt': triggerStartedAt?.toIso8601String(),
      'triggerCompletedAt': triggerCompletedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'completionSource': completionSource?.name,
      'probeSucceeded': probeSucceeded,
      'appcastProbeVersion': appcastProbeVersion,
      'appcastProbeItemCount': appcastProbeItemCount,
      'updateAvailable': updateAvailable,
      'remoteVersion': remoteVersion,
      'remoteDisplayVersion': remoteDisplayVersion,
      'errorMessage': errorMessage,
      'probeErrorMessage': probeErrorMessage,
    };
  }

  static UpdateCheckDiagnostics? fromJson(Map<String, dynamic> json) {
    final checkedAtRaw = json['checkedAt'];
    final configuredFeedUrl = json['configuredFeedUrl'];
    final requestedFeedUrl = json['requestedFeedUrl'];
    if (checkedAtRaw is! String ||
        configuredFeedUrl is! String ||
        requestedFeedUrl is! String) {
      return null;
    }

    final checkedAt = DateTime.tryParse(checkedAtRaw);
    if (checkedAt == null) {
      return null;
    }

    return UpdateCheckDiagnostics(
      checkedAt: checkedAt,
      configuredFeedUrl: configuredFeedUrl,
      requestedFeedUrl: requestedFeedUrl,
      currentVersion: json['currentVersion'] as String?,
      probeRequestUrl: json['probeRequestUrl'] as String?,
      triggerStartedAt: _parseDateTime(json['triggerStartedAt']),
      triggerCompletedAt: _parseDateTime(json['triggerCompletedAt']),
      completedAt: _parseDateTime(json['completedAt']),
      completionSource: _parseCompletionSource(json['completionSource']),
      probeSucceeded: json['probeSucceeded'] as bool?,
      appcastProbeVersion: json['appcastProbeVersion'] as String?,
      appcastProbeItemCount: json['appcastProbeItemCount'] as int?,
      updateAvailable: json['updateAvailable'] as bool?,
      remoteVersion: json['remoteVersion'] as String?,
      remoteDisplayVersion: json['remoteDisplayVersion'] as String?,
      errorMessage: json['errorMessage'] as String?,
      probeErrorMessage: json['probeErrorMessage'] as String?,
    );
  }

  UpdateCheckDiagnostics copyWith({
    DateTime? checkedAt,
    String? configuredFeedUrl,
    String? requestedFeedUrl,
    String? currentVersion,
    String? probeRequestUrl,
    DateTime? triggerStartedAt,
    DateTime? triggerCompletedAt,
    DateTime? completedAt,
    UpdateCheckCompletionSource? completionSource,
    bool? probeSucceeded,
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
      currentVersion: currentVersion ?? this.currentVersion,
      probeRequestUrl: probeRequestUrl ?? this.probeRequestUrl,
      triggerStartedAt: triggerStartedAt ?? this.triggerStartedAt,
      triggerCompletedAt: triggerCompletedAt ?? this.triggerCompletedAt,
      completedAt: completedAt ?? this.completedAt,
      completionSource: completionSource ?? this.completionSource,
      probeSucceeded: probeSucceeded ?? this.probeSucceeded,
      appcastProbeVersion: appcastProbeVersion ?? this.appcastProbeVersion,
      appcastProbeItemCount: appcastProbeItemCount ?? this.appcastProbeItemCount,
      updateAvailable: updateAvailable ?? this.updateAvailable,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      remoteDisplayVersion: remoteDisplayVersion ?? this.remoteDisplayVersion,
      errorMessage: errorMessage ?? this.errorMessage,
      probeErrorMessage: probeErrorMessage ?? this.probeErrorMessage,
    );
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static UpdateCheckCompletionSource? _parseCompletionSource(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    for (final source in UpdateCheckCompletionSource.values) {
      if (source.name == value) {
        return source;
      }
    }
    return null;
  }
}
