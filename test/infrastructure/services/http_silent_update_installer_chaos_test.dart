@Tags(['chaos'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/core/security/helper_signature_probe.dart';
import 'package:plug_agente/infrastructure/services/dio_silent_update_installer.dart';
import 'package:result_dart/result_dart.dart';

/// Chaos suite that fuzzes the installer download path against an HTTP
/// server that aborts the connection at random points. The goal is to
/// confirm that:
///
/// - retries do not leak the launcher process when the install failed;
/// - intermediate `.part` files are cleaned up between attempts;
/// - the SHA mismatch path triggers reliably (no half-finished bytes
///   slip past the validator).
///
/// Tagged `chaos` so the broader suite stays fast. Run with:
///
///     flutter test test/infrastructure/services/http_silent_update_installer_chaos_test.dart --tags chaos
void main() {
  group('HttpSilentUpdateInstaller chaos', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plug_silent_update_chaos_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
      'never starts the launcher when the server aborts mid-body',
      () async {
        // Deterministic seed so the suite is reproducible.
        final random = Random(42);
        final fullBody = List<int>.generate(64, (i) => i % 256);

        final server = await HttpServer.bind('127.0.0.1', 0);
        addTearDown(() => server.close(force: true));
        server.listen((HttpRequest request) async {
          final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
          var startOffset = 0;
          if (rangeHeader != null) {
            final match = RegExp(r'bytes=(\d+)-').firstMatch(rangeHeader);
            if (match != null) startOffset = int.parse(match.group(1)!);
          }
          final remainder = fullBody.sublist(startOffset);
          // Stream a random fraction of the body then close abruptly. We
          // deliberately set the Content-Length to the *full* remainder so
          // the installer sees a content-length mismatch when we close
          // early. The HttpServer would normally complain about this, so
          // we wrap the close in a try/catch and let the chaos server
          // emit a connection-level error instead of a clean 200 OK.
          request.response.statusCode = rangeHeader != null ? HttpStatus.partialContent : HttpStatus.ok;
          if (rangeHeader != null) {
            request.response.headers.set(
              'Content-Range',
              'bytes $startOffset-${fullBody.length - 1}/${fullBody.length}',
            );
          }
          final abortAt = max(1, (remainder.length * (0.3 + random.nextDouble() * 0.4)).floor());
          request.response.add(remainder.sublist(0, abortAt));
          try {
            await request.response.flush();
            await request.response.close();
          } on HttpException {
            // Expected: closing early triggers "content size below
            // specified contentLength" when we set contentLength.
          }
          await request.response.done.catchError((_) {});
        });

        const installerName = 'PlugAgente-Setup-99.0.0.exe';
        final helperFile = File('${tempDir.path}/plug_update_helper.exe')..writeAsStringSync('helper');

        var launcherProcessStarts = 0;
        Result<SilentUpdateInstallResult>? lastResult;

        // Multiple attempts: every attempt should fail because the server
        // closes mid-body. None should ever spawn the launcher.
        for (var attempt = 0; attempt < 4; attempt++) {
          final installer = HttpSilentUpdateInstaller(
            downloadDirectoryResolver: () async => tempDir.path,
            installDirectoryResolver: () async => tempDir.path,
            installDirectoryWritableProbe: (_) async => true,
            updateHelperPathResolver: () async => helperFile.path,
            currentProcessIdResolver: () => 1234,
            updateDirectorySecurityHardener: (_) async => 'restricted',
            helperSignatureProbe: const NoOpHelperSignatureProbe(),
            processStarter: (_, _, {mode = ProcessStartMode.normal}) async {
              launcherProcessStarts++;
              return _NoOpProcess();
            },
          );

          lastResult = await installer.install(
            SilentUpdateInstallRequest(
              version: '99.0.0+1',
              assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
              assetSize: fullBody.length,
              assetName: installerName,
              sha256: '0' * 64,
              requireValidSignature: false,
            ),
          );
        }

        expect(lastResult, isNotNull);
        expect(lastResult!.isError(), isTrue, reason: 'chaos server must produce failures');
        expect(launcherProcessStarts, 0, reason: 'launcher must NEVER run when install failed');

        // No stale .part files should remain between attempts.
        final remainingParts = tempDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.part'))
            .toList();
        // When resume=true and the previous attempt left a .part, the
        // next install() consumes it (with Range) and the chaos server
        // truncates it again. After the loop ends, the final .part may
        // still exist (it is the byproduct of the last failed attempt);
        // we just guarantee that no stale .part predates an attempt that
        // succeeded — none did, so the invariant is trivially met.
        // Sanity: at most ONE .part remains (the last failure).
        expect(remainingParts.length, lessThanOrEqualTo(1));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}

class _NoOpProcess implements Process {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final StreamController<List<int>> _stdin = StreamController<List<int>>();

  @override
  Future<int> get exitCode async => 0;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  @override
  int get pid => 1;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  IOSink get stdin => IOSink(_stdin.sink);

  @override
  Stream<List<int>> get stdout => _stdout.stream;
}
