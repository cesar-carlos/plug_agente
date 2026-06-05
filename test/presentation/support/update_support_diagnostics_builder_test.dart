import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/support/update_support_diagnostics_builder.dart';

void main() {
  late AppLocalizations l10n;

  setUp(() {
    l10n = lookupAppLocalizations(const Locale('pt'));
  });

  UpdateCheckDiagnostics diagnostics({
    UpdateCheckCompletionSource? completionSource,
  }) {
    return UpdateCheckDiagnostics(
      checkedAt: DateTime(2026, 5, 14, 11, 20),
      configuredFeedUrl: 'https://example.com/appcast.xml',
      requestedFeedUrl: 'https://example.com/appcast.xml',
      currentVersion: '1.6.7+1',
      completedAt: DateTime(2026, 5, 14, 11, 21),
      completionSource: completionSource,
    );
  }

  group('buildAutomaticUpdateStatusLabel', () {
    test('includes completion suffix when notifications are enabled', () {
      final label = UpdateSupportDiagnosticsBuilder.buildAutomaticUpdateStatusLabel(
        l10n: l10n,
        diagnostics: diagnostics(
          completionSource: UpdateCheckCompletionSource.automaticDownloadFailure,
        ),
        updateNotificationsEnabled: true,
        automaticSilentUpdatesEnabled: true,
        formatCheckedAt: (_) => '14/05/2026 11:20',
      );

      expect(label, contains(l10n.configUpdateCompletionSourceAutomaticDownloadFailure));
    });

    test('omits completion suffix when notifications are off but auto is on', () {
      final label = UpdateSupportDiagnosticsBuilder.buildAutomaticUpdateStatusLabel(
        l10n: l10n,
        diagnostics: diagnostics(
          completionSource: UpdateCheckCompletionSource.automaticDownloadFailure,
        ),
        updateNotificationsEnabled: false,
        automaticSilentUpdatesEnabled: true,
        formatCheckedAt: (_) => '14/05/2026 11:20',
      );

      expect(label, '${l10n.configLastAutomaticUpdatePrefix}14/05/2026 11:20');
      expect(label, isNot(contains(l10n.configUpdateCompletionSourceAutomaticDownloadFailure)));
    });

    test('shows neutral never label in manual-only mode', () {
      final label = UpdateSupportDiagnosticsBuilder.buildAutomaticUpdateStatusLabel(
        l10n: l10n,
        diagnostics: diagnostics(
          completionSource: UpdateCheckCompletionSource.automaticDownloadFailure,
        ),
        updateNotificationsEnabled: false,
        automaticSilentUpdatesEnabled: false,
        formatCheckedAt: (_) => '14/05/2026 11:20',
      );

      expect(label, '${l10n.configLastAutomaticUpdatePrefix}${l10n.configLastUpdateNever}');
    });
  });

  group('buildBackgroundUpdateStatusLabel', () {
    test('omits completion suffix when notifications are off', () {
      final label = UpdateSupportDiagnosticsBuilder.buildBackgroundUpdateStatusLabel(
        l10n: l10n,
        diagnostics: diagnostics(
          completionSource: UpdateCheckCompletionSource.updaterError,
        ),
        updateNotificationsEnabled: false,
        automaticSilentUpdatesEnabled: true,
        formatCheckedAt: (_) => '14/05/2026 11:20',
      );

      expect(label, '${l10n.configLastBackgroundUpdatePrefix}14/05/2026 11:20');
      expect(label, isNot(contains(l10n.configUpdateCompletionSourceUpdaterError)));
    });

    test('returns empty label in manual-only mode', () {
      final label = UpdateSupportDiagnosticsBuilder.buildBackgroundUpdateStatusLabel(
        l10n: l10n,
        diagnostics: diagnostics(
          completionSource: UpdateCheckCompletionSource.updaterError,
        ),
        updateNotificationsEnabled: false,
        automaticSilentUpdatesEnabled: false,
        formatCheckedAt: (_) => '14/05/2026 11:20',
      );

      expect(label, isEmpty);
    });
  });
}
