import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/policies/app_preferences_policy.dart';

void main() {
  group('AppPreferencesPolicy', () {
    group('isManualOnlyUpdateMode', () {
      test('should be true only when both update modes are disabled', () {
        expect(
          AppPreferencesPolicy.isManualOnlyUpdateMode(
            updateNotificationsEnabled: false,
            automaticSilentUpdatesEnabled: false,
          ),
          isTrue,
        );
        expect(
          AppPreferencesPolicy.isManualOnlyUpdateMode(
            updateNotificationsEnabled: true,
            automaticSilentUpdatesEnabled: false,
          ),
          isFalse,
        );
        expect(
          AppPreferencesPolicy.isManualOnlyUpdateMode(
            updateNotificationsEnabled: false,
            automaticSilentUpdatesEnabled: true,
          ),
          isFalse,
        );
        expect(
          AppPreferencesPolicy.isManualOnlyUpdateMode(
            updateNotificationsEnabled: true,
            automaticSilentUpdatesEnabled: true,
          ),
          isFalse,
        );
      });
    });

    group('shouldShowUpdateBanner', () {
      test('should follow update notification preference', () {
        expect(
          AppPreferencesPolicy.shouldShowUpdateBanner(updateNotificationsEnabled: true),
          isTrue,
        );
        expect(
          AppPreferencesPolicy.shouldShowUpdateBanner(updateNotificationsEnabled: false),
          isFalse,
        );
      });
    });

    group('shouldStartMinimizedAtLaunch', () {
      test('should stay in tray on autostart when tray is available', () {
        expect(
          AppPreferencesPolicy.shouldStartMinimizedAtLaunch(
            supportsTray: true,
            isAutostartLaunch: true,
          ),
          isTrue,
        );
        expect(
          AppPreferencesPolicy.shouldStartMinimizedAtLaunch(
            supportsTray: true,
            isAutostartLaunch: false,
          ),
          isFalse,
        );
        expect(
          AppPreferencesPolicy.shouldStartMinimizedAtLaunch(
            supportsTray: false,
            isAutostartLaunch: true,
          ),
          isFalse,
        );
      });
    });

    group('autostart window bootstrap', () {
      test('should hide during autostart bootstrap and never reveal on login', () {
        expect(
          AppPreferencesPolicy.shouldHideWindowDuringAutostartBootstrap(
            isAutostartLaunch: true,
          ),
          isTrue,
        );
        expect(
          AppPreferencesPolicy.shouldHideWindowDuringAutostartBootstrap(
            isAutostartLaunch: false,
          ),
          isFalse,
        );
        expect(
          AppPreferencesPolicy.shouldRevealWindowAfterAutostartBootstrap(
            isAutostartLaunch: true,
          ),
          isFalse,
        );
        expect(
          AppPreferencesPolicy.shouldRevealWindowAfterAutostartBootstrap(
            isAutostartLaunch: false,
          ),
          isFalse,
        );
      });
    });

    group('shouldRunWinSparkleBackgroundChecks', () {
      test('should run when notifications are on and silent updates are off', () {
        expect(
          AppPreferencesPolicy.shouldRunWinSparkleBackgroundChecks(
            updateNotificationsEnabled: true,
            automaticSilentUpdatesEnabled: false,
          ),
          isTrue,
        );
        expect(
          AppPreferencesPolicy.shouldRunWinSparkleBackgroundChecks(
            updateNotificationsEnabled: false,
            automaticSilentUpdatesEnabled: false,
          ),
          isFalse,
        );
        expect(
          AppPreferencesPolicy.shouldRunWinSparkleBackgroundChecks(
            updateNotificationsEnabled: true,
            automaticSilentUpdatesEnabled: true,
          ),
          isFalse,
        );
      });
    });
  });
}
