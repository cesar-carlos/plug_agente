import 'package:plug_agente/core/runtime/windows_version_info.dart';

enum RuntimeDetectionSource {
  rtlGetVersion,
  platformOperatingSystemVersion,
  detectionFailed,
}

class RuntimeDetectionDiagnostics {
  const RuntimeDetectionDiagnostics({
    required this.source,
    this.versionInfo,
    this.rawOperatingSystemVersion,
    this.failureMessage,
  });

  factory RuntimeDetectionDiagnostics.detected({
    required RuntimeDetectionSource source,
    required WindowsVersionInfo versionInfo,
    String? rawOperatingSystemVersion,
  }) {
    return RuntimeDetectionDiagnostics(
      source: source,
      versionInfo: versionInfo,
      rawOperatingSystemVersion: rawOperatingSystemVersion,
    );
  }

  factory RuntimeDetectionDiagnostics.failed({
    required String failureMessage,
    String? rawOperatingSystemVersion,
  }) {
    return RuntimeDetectionDiagnostics(
      source: RuntimeDetectionSource.detectionFailed,
      rawOperatingSystemVersion: rawOperatingSystemVersion,
      failureMessage: failureMessage,
    );
  }

  final RuntimeDetectionSource source;
  final WindowsVersionInfo? versionInfo;
  final String? rawOperatingSystemVersion;
  final String? failureMessage;

  bool get isSuccessful => versionInfo != null;

  String get sourceName {
    return switch (source) {
      RuntimeDetectionSource.rtlGetVersion => 'rtl_get_version',
      RuntimeDetectionSource.platformOperatingSystemVersion => 'platform_operating_system_version',
      RuntimeDetectionSource.detectionFailed => 'detection_failed',
    };
  }
}
