import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/runtime/i_windows_runtime_probe.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/runtime/runtime_mode.dart';
import 'package:plug_agente/core/runtime/windows_version_info.dart';
import 'package:plug_agente/presentation/boot/app_initializer.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  test('passes detected runtime diagnostics through bootstrap setup callback', () async {
    var capturedCapabilities = null as RuntimeCapabilities?;
    var capturedDiagnostics = null as RuntimeDetectionDiagnostics?;
    var bootstrapPhasesRan = false;
    var desktopFeaturesInitialized = false;

    final initializer = AppInitializer(
      runtimeProbe: _FakeWindowsRuntimeProbe(
        result: const Success(
          WindowsVersionInfo(
            majorVersion: 10,
            minorVersion: 0,
            buildNumber: 26200,
            isServer: false,
            productName: 'Windows 11 Pro',
          ),
        ),
        diagnostics: RuntimeDetectionDiagnostics.detected(
          source: RuntimeDetectionSource.rtlGetVersion,
          versionInfo: const WindowsVersionInfo(
            majorVersion: 10,
            minorVersion: 0,
            buildNumber: 26200,
            isServer: false,
            productName: 'Windows 11 Pro',
          ),
        ),
      ),
      setupDependenciesOverride:
          ({
            required RuntimeCapabilities capabilities,
            RuntimeDetectionDiagnostics? runtimeDetectionDiagnostics,
          }) async {
            capturedCapabilities = capabilities;
            capturedDiagnostics = runtimeDetectionDiagnostics;
          },
      bootstrapPhasesOverride: () async {
        bootstrapPhasesRan = true;
      },
      initializeDesktopFeaturesOverride: (capabilities) async {
        desktopFeaturesInitialized = true;
      },
      resolveInitialRouteOverride: (_) => '/agent-actions',
    );

    final result = await initializer.initialize(const <String>[]);

    expect(result.initialRoute, '/agent-actions');
    expect(result.capabilities.mode, RuntimeMode.full);
    expect(capturedCapabilities?.mode, RuntimeMode.full);
    expect(capturedDiagnostics?.source, RuntimeDetectionSource.rtlGetVersion);
    expect(capturedDiagnostics?.versionInfo?.versionString, '10.0.26200');
    expect(bootstrapPhasesRan, isTrue);
    expect(desktopFeaturesInitialized, isTrue);
  });

  test('passes fallback failed diagnostics when runtime probe fails', () async {
    var capturedCapabilities = null as RuntimeCapabilities?;
    var capturedDiagnostics = null as RuntimeDetectionDiagnostics?;

    final initializer = AppInitializer(
      runtimeProbe: _FakeWindowsRuntimeProbe(
        result: Failure<WindowsVersionInfo, Exception>(Exception('probe failed')),
        diagnostics: RuntimeDetectionDiagnostics.failed(
          failureMessage: 'probe failed',
          rawOperatingSystemVersion: 'Windows mystery build',
        ),
      ),
      setupDependenciesOverride:
          ({
            required RuntimeCapabilities capabilities,
            RuntimeDetectionDiagnostics? runtimeDetectionDiagnostics,
          }) async {
            capturedCapabilities = capabilities;
            capturedDiagnostics = runtimeDetectionDiagnostics;
          },
      bootstrapPhasesOverride: () async {},
      initializeDesktopFeaturesOverride: (capabilities) async {},
    );

    final result = await initializer.initialize(const <String>[]);

    expect(result.capabilities.mode, RuntimeMode.degraded);
    expect(capturedCapabilities?.isDegraded, isTrue);
    expect(capturedDiagnostics?.source, RuntimeDetectionSource.detectionFailed);
    expect(capturedDiagnostics?.rawOperatingSystemVersion, 'Windows mystery build');
  });
}

class _FakeWindowsRuntimeProbe implements IWindowsRuntimeProbe {
  _FakeWindowsRuntimeProbe({
    required this.result,
    this.diagnostics,
  });

  final Result<WindowsVersionInfo> result;

  final RuntimeDetectionDiagnostics? diagnostics;

  @override
  RuntimeDetectionDiagnostics? get lastDiagnostics => diagnostics;

  @override
  Future<Result<WindowsVersionInfo>> detect() async => result;
}
