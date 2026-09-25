import 'dart:typed_data';

import 'package:plug_agente/core/constants/launch_args_constants.dart';
import 'package:plug_agente/infrastructure/services/startup_registry_snapshot.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_approved_store.dart';
import 'package:plug_agente/infrastructure/services/windows_startup_run_value_reader.dart';

/// Renders the registry half of the startup diagnostic for support tickets.
abstract final class StartupRegistryDiagnosticReport {
  static String render({
    required String expectedExecutable,
    required StartupRegistrySnapshot snapshot,
    required StartupApprovedReadResult approved,
  }) {
    final buffer = StringBuffer()
      ..writeln('Expected executable: $expectedExecutable')
      ..writeln('Expected autostart arg: ${LaunchArgsConstants.autostartArg}')
      ..writeln()
      ..writeln('StartupApproved (HKCU): ${approved.status.name}')
      ..writeln('StartupApproved blocked by Startup Apps: ${approved.isEffectivelyDisabled}');
    if (approved.nativeStatus != null) {
      buffer.writeln('StartupApproved native status: ${approved.nativeStatus}');
    }
    final rawBytes = approved.rawBytes;
    if (rawBytes != null) {
      buffer.writeln('StartupApproved raw bytes: ${_hex(rawBytes)}');
    }
    buffer.writeln();

    for (final result in snapshot.results) {
      _writeScope(buffer, result, expectedExecutable);
    }

    final unreadable = snapshot.results
        .where((result) => result.isMachineScopeUnreadable)
        .map((result) => result.scope.label)
        .join(', ');
    buffer
      ..writeln('Needs repair: ${snapshot.needsRepair(approved: approved, expectedExecutable: expectedExecutable)}')
      ..writeln('Unreadable machine scopes: ${unreadable.isEmpty ? 'none' : unreadable}')
      ..writeln('Existing entry count: ${snapshot.existing.length}');

    return buffer.toString().trimRight();
  }

  static void _writeScope(StringBuffer buffer, StartupRegistryQueryResult result, String expectedExecutable) {
    buffer
      ..writeln('Scope: ${result.scope.label}')
      ..writeln('  Exists: ${result.exists}');
    final entry = result.entry;
    if (entry != null) {
      buffer
        ..writeln('  Executable: ${entry.executablePath}')
        ..writeln('  Has autostart arg: ${entry.hasAutostartArgument}')
        ..writeln('  Healthy for current exe: ${entry.isHealthyFor(expectedExecutable)}')
        ..writeln('  Raw value: ${entry.rawValue}');
    } else if (result.readResult.status == StartupRunValueReadStatus.failed) {
      buffer.writeln('  Read failed (Win32 status: ${result.readResult.nativeStatus})');
    } else if (result.readResult.status == StartupRunValueReadStatus.accessDenied) {
      buffer.writeln('  Read denied (Win32 status: ${result.readResult.nativeStatus})');
    }
    buffer.writeln();
  }

  static String _hex(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
  }
}
