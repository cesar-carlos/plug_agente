import 'package:auto_updater/auto_updater.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

class FakeAutoUpdaterGateway implements IAutoUpdaterGateway {
  UpdaterListener? listener;
  final List<String> feedUrls = <String>[];
  int? interval;
  bool? lastInBackground;
  Exception? checkError;
  Future<void> Function()? onCheckForUpdates;

  @override
  void addListener(UpdaterListener listener) {
    this.listener = listener;
  }

  @override
  Future<void> setFeedURL(String feedUrl) async {
    feedUrls.add(feedUrl);
  }

  @override
  Future<void> checkForUpdates({required bool inBackground}) async {
    lastInBackground = inBackground;
    if (checkError != null) {
      throw checkError!;
    }
    if (onCheckForUpdates != null) {
      await onCheckForUpdates!.call();
    }
  }

  @override
  Future<void> setScheduledCheckInterval(int interval) async {
    this.interval = interval;
  }
}

class FakeAppcastProbeService implements IAppcastProbeService {
  AppcastProbeResult result = const AppcastProbeResult(
    requestUrl: 'https://example.com/appcast.xml',
    latestVersion: '1.0.99+1',
    itemCount: 1,
  );
  String? lastProbeUrl;

  @override
  Future<AppcastProbeResult> probeLatest({
    required String feedUrl,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    lastProbeUrl = feedUrl;
    return AppcastProbeResult(
      requestUrl: feedUrl,
      latestVersion: result.latestVersion,
      itemCount: result.itemCount,
      errorMessage: result.errorMessage,
    );
  }
}

void main() {
  group('AutoUpdateOrchestrator', () {
    setUp(() {
      dotenv.clean();
      dotenv.loadFromString(
        envString:
            'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml\nAUTO_UPDATE_CHECK_INTERVAL_SECONDS=3600',
      );
    });

    group('isAvailable', () {
      test('returns false when supportsAutoUpdate is false', () {
        final capabilities = RuntimeCapabilities.degraded(
          reasons: ['Test degradation'],
        );
        final orchestrator = AutoUpdateOrchestrator(capabilities);

        expect(orchestrator.isAvailable, isFalse);
      });

      test('returns true when supported and feed is configured', () {
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
        );

        expect(orchestrator.isAvailable, isTrue);
      });
    });

    group('initialize', () {
      test('configures feed, interval and listener', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
        );

        await orchestrator.initialize();

        expect(fakeGateway.listener, isNotNull);
        expect(fakeGateway.feedUrls.single, 'https://example.com/appcast.xml');
        expect(fakeGateway.interval, 3600);
      });
    });

    group('checkManual', () {
      test('returns Failure when supportsAutoUpdate is false', () async {
        final capabilities = RuntimeCapabilities.degraded(
          reasons: ['Test degradation'],
        );
        final orchestrator = AutoUpdateOrchestrator(capabilities);

        final result = await orchestrator.checkManual();

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final f = failure as domain.Failure;
            expect(f.message, contains('not supported'));
          },
        );
      });

      test('returns Success(true) when update is available', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final fakeProbe = FakeAppcastProbeService();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: fakeProbe,
        );

        fakeGateway.onCheckForUpdates = () async {
          fakeGateway.listener?.onUpdaterUpdateAvailable(null);
        };

        final result = await orchestrator.checkManual();

        expect(result.isSuccess(), isTrue);
        result.fold(
          (isUpdateAvailable) => expect(isUpdateAvailable, isTrue),
          (_) => fail('Expected success'),
        );
        expect(fakeGateway.lastInBackground, isFalse);
        expect(fakeGateway.feedUrls.length, 2);
        expect(fakeGateway.feedUrls.last, contains('cb='));
        expect(fakeProbe.lastProbeUrl, equals(fakeGateway.feedUrls.last));
        expect(orchestrator.lastManualDiagnostics?.updateAvailable, isTrue);
        expect(
          orchestrator.lastManualDiagnostics?.appcastProbeVersion,
          '1.0.99+1',
        );
      });

      test('returns Success(false) when update is not available', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '1.0.13+14',
            itemCount: 4,
          );
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: fakeProbe,
        );

        fakeGateway.onCheckForUpdates = () async {
          fakeGateway.listener?.onUpdaterUpdateNotAvailable(null);
        };

        final result = await orchestrator.checkManual();

        expect(result.isSuccess(), isTrue);
        result.fold(
          (isUpdateAvailable) => expect(isUpdateAvailable, isFalse),
          (_) => fail('Expected success'),
        );
        expect(fakeGateway.lastInBackground, isFalse);
        expect(orchestrator.lastManualDiagnostics?.updateAvailable, isFalse);
        expect(
          orchestrator.lastManualDiagnostics?.appcastProbeVersion,
          '1.0.13+14',
        );
      });

      test('returns Failure when check trigger throws', () async {
        final fakeGateway = FakeAutoUpdaterGateway()
          ..checkError = Exception('boom');
        final fakeProbe = FakeAppcastProbeService();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: fakeProbe,
        );

        final result = await orchestrator.checkManual();

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final f = failure as domain.Failure;
            expect(f.message, contains('Failed to trigger update check'));
          },
        );
        expect(
          orchestrator.lastManualDiagnostics?.errorMessage,
          contains('Failed to trigger update check'),
        );
      });
    });
  });
}
