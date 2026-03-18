import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/update_service.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

void main() {
  group('UpdateService', () {
    test('returns configuration failure when URL is empty', () async {
      final service = UpdateService('');

      final result = await service.checkForUpdates();
      final failure = result.exceptionOrNull()! as domain.ConfigurationFailure;

      expect(result.isError(), isTrue);
      expect(
        failure.message,
        'Auto-update is not configured. Set AUTO_UPDATE_FEED_URL with a Sparkle feed (.xml).',
      );
      expect(failure.context, containsPair('operation', 'checkForUpdates'));
    });

    test('returns configuration failure when URL is not Sparkle XML', () async {
      final service = UpdateService('https://updates.example.com');

      final result = await service.checkForUpdates();
      final failure = result.exceptionOrNull()! as domain.ConfigurationFailure;

      expect(result.isError(), isTrue);
      expect(
        failure.message,
        'Auto-update is not configured. Set AUTO_UPDATE_FEED_URL with a Sparkle feed (.xml).',
      );
      expect(failure.context, containsPair('operation', 'checkForUpdates'));
    });
  });
}
