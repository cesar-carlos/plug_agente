import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/application/services/silent_update_failure.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/core/security/helper_signature_probe.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/services/http_silent_update_installer.dart';

void main() {
  group('HttpSilentUpdateInstaller', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('plug_silent_update_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('downloads, validates SHA-256 and starts writable-directory launcher', () async {
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      String? executable;
      List<String>? arguments;
      ProcessStartMode? capturedMode;
      final installDirectory = p.join(tempDir.path, 'Plug Agente');
      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => installDirectory,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 1234,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        processStarter: (path, args, {mode = ProcessStartMode.normal}) async {
          executable = path;
          arguments = args;
          capturedMode = mode;
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isSuccess(), isTrue);
      SilentUpdateInstallResult? success;
      result.fold((value) => success = value, (_) => fail('Expected success'));
      expect(executable, success!.launcherPath);
      expect(capturedMode, ProcessStartMode.detached);
      expect(success!.strategy, SilentUpdateInstallStrategy.currentUserThenElevated);
      expect(success!.installDirectoryWritable, isTrue);
      expect(success!.installDirectory, installDirectory);
      expect(success!.appPid, 1234);
      expect(success!.updateDirectorySecurityStatus, 'restricted');
      expect(File(success!.installerPath).readAsStringSync(), 'hello');
      expect(File('${success!.installerPath}.part').existsSync(), isFalse);
      expect(File(success!.launcherPath).readAsStringSync(), 'helper');
      // Helper SHA-256 fingerprint is captured for diagnostics; the exact
      // digest depends on the synthetic helper bytes, so we only validate the
      // shape (lowercase 64-char hex) here.
      expect(success!.helperSha256, isNotNull);
      expect(success!.helperSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        arguments,
        <String>[
          '--version',
          '99.0.0+1',
          '--installer',
          success!.installerPath,
          '--install-dir',
          installDirectory,
          '--log',
          success!.logPath,
          '--status',
          success!.launcherStatusPath,
          '--app-pid',
          '1234',
          '--asset-size',
          '5',
          '--sha256',
          '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          '--try-current-user-first=true',
          '--require-valid-signature=false',
          '--wait-pid-timeout-seconds',
          '45',
        ],
      );
    });

    test('resumes a partial .part by issuing a Range request (server returns 206)', () async {
      // Pre-populate a .part with the first 2 bytes of 'hello'.
      const installerName = 'PlugAgente-Setup-99.0.0.exe';
      final partFile = File(p.join(tempDir.path, '$installerName.part'))..writeAsBytesSync(utf8.encode('he'));

      Map<String, String>? receivedHeaders;
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest request) async {
        receivedHeaders = <String, String>{};
        request.headers.forEach((name, values) {
          receivedHeaders![name] = values.join(',');
        });
        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        final remainder = utf8.encode('llo'); // bytes 2..4 of 'hello'
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.contentLength = remainder.length
          ..headers.set('Content-Range', 'bytes 2-4/5');
        if (rangeHeader == null) {
          // Should not happen with resume=true and an existing .part.
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentLength = utf8.encode('hello').length;
          request.response.add(utf8.encode('hello'));
        } else {
          request.response.add(remainder);
        }
        await request.response.close();
      });

      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 1234,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        helperSignatureProbe: const NoOpHelperSignatureProbe(),
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async => _FakeProcess(),
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: installerName,
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(receivedHeaders?[HttpHeaders.rangeHeader], 'bytes=2-');
      // Final installer must contain the full 'hello' (resumed bytes + new bytes).
      result.fold(
        (success) => expect(File(success.installerPath).readAsStringSync(), 'hello'),
        (_) => fail('Expected success'),
      );
      expect(partFile.existsSync(), isFalse, reason: '.part must be renamed to .exe on success');
    });

    test('restarts from zero when server ignores Range and returns 200', () async {
      const installerName = 'PlugAgente-Setup-99.0.0.exe';
      // Stale .part has 2 bytes; if server ignores Range, those would corrupt
      // the file unless the installer truncates first.
      File(p.join(tempDir.path, '$installerName.part')).writeAsBytesSync(utf8.encode('xy'));

      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest request) async {
        // Pretend the server does not implement Range.
        final body = utf8.encode('hello');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentLength = body.length
          ..add(body);
        await request.response.close();
      });

      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 1234,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        helperSignatureProbe: const NoOpHelperSignatureProbe(),
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async => _FakeProcess(),
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: installerName,
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isSuccess(), isTrue);
      result.fold(
        (success) => expect(File(success.installerPath).readAsStringSync(), 'hello'),
        (_) => fail('Expected success'),
      );
    });

    test('does not send Range when allowDownloadResume=false', () async {
      const installerName = 'PlugAgente-Setup-99.0.0.exe';
      File(p.join(tempDir.path, '$installerName.part')).writeAsBytesSync(utf8.encode('xy'));

      String? rangeHeader;
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest request) async {
        rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        final body = utf8.encode('hello');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentLength = body.length
          ..add(body);
        await request.response.close();
      });

      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 1234,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        helperSignatureProbe: const NoOpHelperSignatureProbe(),
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async => _FakeProcess(),
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: installerName,
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
          allowDownloadResume: false,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(rangeHeader, isNull, reason: 'opt-out must not negotiate Range');
    });

    test('aborts when download directory has insufficient free space', () async {
      var processStarted = false;
      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 1234,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        // Free space = 4 bytes; asset = 5 bytes; required = 10 -> blocks.
        diskFreeSpaceResolver: (_) async => 4,
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async {
          processStarted = true;
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        const SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:9/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(processStarted, isFalse);
      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected ValidationFailure for insufficient disk space'),
        (failure) {
          expect(failure, isA<domain.ValidationFailure>());
          final context = (failure as domain.Failure).context;
          expect(context['validation_code'], 'insufficient_disk_space');
          expect(context['free_bytes'], 4);
          expect(context['required_bytes'], 10);
        },
      );
    });

    test('skips disk-space check when resolver returns null (best-effort)', () async {
      // null free-space means the platform check was unavailable; the install
      // must still proceed so a degraded environment is not a hard outage.
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 1234,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        diskFreeSpaceResolver: (_) async => null,
        helperSignatureProbe: const NoOpHelperSignatureProbe(),
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async => _FakeProcess(),
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isSuccess(), isTrue);
    });

    test('accepts when free space matches required budget exactly', () async {
      // assetSize=5, budget multiplier=2, required=10; free=10 should pass.
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 1234,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        diskFreeSpaceResolver: (_) async => 10,
        helperSignatureProbe: const NoOpHelperSignatureProbe(),
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async => _FakeProcess(),
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isSuccess(), isTrue);
    });

    test('rejects launch when helper signature is invalid and requireValidSignature=true', () async {
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      var processStarted = false;
      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 1234,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        helperSignatureProbe: const _StubHelperSignatureProbe(HelperSignatureStatus.invalid),
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async {
          processStarted = true;
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: true,
        ),
      );

      expect(processStarted, isFalse, reason: 'invalid helper signature must block launch');
      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected ValidationFailure'),
        (failure) {
          expect(failure, isA<domain.ValidationFailure>());
          final context = (failure as domain.Failure).context;
          expect(context['validation_code'], 'helper_signature_invalid');
          expect(context['helper_signature_status'], 'invalid');
        },
      );
    });

    test('allows launch when helper signature is invalid but requireValidSignature=false', () async {
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      var processStarted = false;
      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 1234,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        helperSignatureProbe: const _StubHelperSignatureProbe(HelperSignatureStatus.invalid),
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async {
          processStarted = true;
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(processStarted, isTrue, reason: 'best-effort mode must still launch');
      expect(result.isSuccess(), isTrue);
      result.fold(
        (success) => expect(success.helperSignatureStatus, 'invalid'),
        (_) => fail('Expected success'),
      );
    });

    test('does not invoke helper signature probe when probe is the NoOp impl', () async {
      // NoOp returns unknown — combined with requireValidSignature=false,
      // the install path remains best-effort, mirroring the default behavior
      // on non-Windows test agents.
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 1234,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        helperSignatureProbe: const NoOpHelperSignatureProbe(),
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async => _FakeProcess(),
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isSuccess(), isTrue);
      result.fold(
        (success) => expect(success.helperSignatureStatus, 'unknown'),
        (_) => fail('Expected success'),
      );
    });

    test('rejects external HTTP asset URL before downloading', () async {
      var processStarted = false;
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async {
          processStarted = true;
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        const SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://updates.example.com/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isError(), isTrue);
      expect(processStarted, isFalse);
      expect(tempDir.listSync(), isEmpty);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ValidationFailure>()),
      );
    });

    test('returns network failure when download does not finish before timeout', () async {
      var processStarted = false;
      final httpClient = _NeverCompletingHttpClient();
      final installer = HttpSilentUpdateInstaller(
        downloadTimeout: const Duration(milliseconds: 50),
        httpClientFactory: () => httpClient,
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async {
          processStarted = true;
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        const SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isError(), isTrue);
      expect(processStarted, isFalse);
      expect(httpClient.closedWithForce, isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) {
          expect(failure, isA<domain.NetworkFailure>());
          final typedFailure = failure as domain.Failure;
          expect(typedFailure.message, contains('timed out'));
          expect(typedFailure.context['timeout_ms'], 50);
        },
      );
    });

    test('uses elevated-only launcher when install directory is not writable', () async {
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      final installDirectory = p.join(tempDir.path, 'Program Files', 'Plug Agente');
      List<String>? arguments;
      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => installDirectory,
        installDirectoryWritableProbe: (_) async => false,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 5678,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        processStarter: (_, args, {mode = ProcessStartMode.normal}) async {
          arguments = args;
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isSuccess(), isTrue);
      SilentUpdateInstallResult? success;
      result.fold((value) => success = value, (_) => fail('Expected success'));
      expect(success!.strategy, SilentUpdateInstallStrategy.elevatedOnly);
      expect(success!.installDirectoryWritable, isFalse);
      expect(File(success!.launcherPath).readAsStringSync(), 'helper');
      expect(arguments, contains('--try-current-user-first=false'));
      expect(arguments, containsAll(<String>['--install-dir', installDirectory, '--app-pid', '5678']));
    });

    test('rejects SHA-256 mismatch before starting process', () async {
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      var processStarted = false;
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async {
          processStarted = true;
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '0000000000000000000000000000000000000000000000000000000000000000',
          requireValidSignature: false,
        ),
      );

      expect(result.isError(), isTrue);
      expect(processStarted, isFalse);
      expect(tempDir.listSync(), isEmpty);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ValidationFailure>()),
      );
    });

    test('rejects size mismatch before starting process', () async {
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      var processStarted = false;
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async {
          processStarted = true;
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 6,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isError(), isTrue);
      expect(processStarted, isFalse);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ValidationFailure>()),
      );
    });

    test('aborts download when response exceeds appcast length', () async {
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      var processStarted = false;
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async {
          processStarted = true;
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 4,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isError(), isTrue);
      expect(processStarted, isFalse);
      expect(tempDir.listSync(), isEmpty);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ValidationFailure>()),
      );
    });

    test('returns failure when process cannot be started', () async {
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async {
          throw const ProcessException('setup.exe', <String>[], 'boom');
        },
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ServerFailure>()),
      );
    });

    test('returns failure when installed update helper is missing', () async {
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      var processStarted = false;
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => p.join(tempDir.path, 'missing-helper.exe'),
        processStarter: (_, _, {mode = ProcessStartMode.normal}) async {
          processStarted = true;
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(result.isError(), isTrue);
      expect(processStarted, isFalse);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ServerFailure>()),
      );
    });

    test('aborts before download when cancellation is requested up front', () async {
      var processStarted = false;
      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 1,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        processStarter: (path, args, {mode = ProcessStartMode.normal}) async {
          processStarted = true;
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:9/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
          cancelRequested: () => true,
        ),
      );

      expect(processStarted, isFalse);
      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure when cancellation is requested'),
        (failure) {
          // Cancellation is now a typed sealed failure; the legacy
          // context marker stays in place for operators inspecting
          // persisted diagnostics.
          expect(failure, isA<SilentInstallCancellationFailure>());
          final context = (failure as domain.Failure).context;
          expect(context[SilentUpdateInstallRequest.cancellationContextKey], isTrue);
        },
      );
    });

    test('aborts download mid-stream when cancellation flips true', () async {
      // Server slow-drips bytes so we can observe the cancellation reaching the
      // download loop between chunks rather than after completion.
      final body = utf8.encode('hello');
      final server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => server.close(force: true));
      server.listen((HttpRequest request) async {
        request.response.contentLength = body.length;
        request.response.add(body.sublist(0, 2));
        await request.response.flush();
        // Hang the rest of the body so the cancellation flag has time to flip
        // mid-stream. The installer must break out of the await-for loop.
        await Future<void>.delayed(const Duration(seconds: 5));
        await request.response.close();
      });

      var processStarted = false;
      var cancelFlag = false;
      final helperFile = _createHelper(tempDir);
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 1,
        updateDirectorySecurityHardener: (_) async => 'restricted',
        processStarter: (path, args, {mode = ProcessStartMode.normal}) async {
          processStarted = true;
          return _FakeProcess();
        },
      );

      final installFuture = installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: body.length,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
          cancelRequested: () => cancelFlag,
        ),
      );

      // Wait for the first chunk to arrive, then trip cancellation.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      cancelFlag = true;

      final result = await installFuture;

      expect(processStarted, isFalse, reason: 'cancelled download must not spawn helper');
      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected cancellation failure'),
        (failure) {
          final context = (failure as domain.Failure).context;
          expect(context[SilentUpdateInstallRequest.cancellationContextKey], isTrue);
        },
      );
      // The partial download must be cleaned up by the installer.
      final partFile = File(p.join(tempDir.path, 'PlugAgente-Setup-99.0.0.exe.part'));
      expect(partFile.existsSync(), isFalse);
    });

    test('proceeds with install when directory hardener reports failedTimeout', () async {
      final server = await _serveBytes(utf8.encode('hello'));
      addTearDown(() => server.close(force: true));
      final helperFile = _createHelper(tempDir);
      String? hardenedDirectory;
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
        installDirectoryResolver: () async => tempDir.path,
        installDirectoryWritableProbe: (_) async => true,
        updateHelperPathResolver: () async => helperFile.path,
        currentProcessIdResolver: () => 4321,
        updateDirectorySecurityHardener: (dir) async {
          hardenedDirectory = dir;
          // The production hardener swallows TimeoutException and returns
          // 'failedTimeout' instead of hanging the install pipeline.
          return 'failedTimeout';
        },
        processStarter: (path, args, {mode = ProcessStartMode.normal}) async {
          return _FakeProcess();
        },
      );

      final result = await installer.install(
        SilentUpdateInstallRequest(
          version: '99.0.0+1',
          assetUrl: 'http://127.0.0.1:${server.port}/PlugAgente-Setup-99.0.0.exe',
          assetSize: 5,
          assetName: 'PlugAgente-Setup-99.0.0.exe',
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          requireValidSignature: false,
        ),
      );

      expect(hardenedDirectory, tempDir.path);
      expect(result.isSuccess(), isTrue);
      result.fold(
        (success) => expect(success.updateDirectorySecurityStatus, 'failedTimeout'),
        (_) => fail('Expected install to succeed despite hardener timeout'),
      );
    });

    test('cleans obsolete artifacts while keeping recent files', () async {
      final installer = HttpSilentUpdateInstaller(
        downloadDirectoryResolver: () async => tempDir.path,
      );
      final oldFile = File(p.join(tempDir.path, 'PlugAgente-Setup-old.exe'))..writeAsStringSync('old');
      oldFile.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 31)));
      for (var index = 0; index < 4; index++) {
        final file = File(p.join(tempDir.path, 'PlugAgente-Update-$index.log'))..writeAsStringSync('$index');
        file.setLastModifiedSync(DateTime.now().subtract(Duration(minutes: index)));
      }

      final result = await installer.cleanupObsoleteArtifacts();

      expect(result.isSuccess(), isTrue);
      expect(oldFile.existsSync(), isFalse);
      expect(File(p.join(tempDir.path, 'PlugAgente-Update-0.log')).existsSync(), isTrue);
      expect(File(p.join(tempDir.path, 'PlugAgente-Update-1.log')).existsSync(), isTrue);
      expect(File(p.join(tempDir.path, 'PlugAgente-Update-2.log')).existsSync(), isTrue);
      expect(File(p.join(tempDir.path, 'PlugAgente-Update-3.log')).existsSync(), isFalse);
    });
  });
}

File _createHelper(Directory directory) {
  final file = File(p.join(directory.path, 'installed_plug_update_helper.exe'));
  file.writeAsStringSync('helper');
  return file;
}

Future<HttpServer> _serveBytes(List<int> bytes) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentLength = bytes.length
      ..add(bytes);
    await request.response.close();
  });
  return server;
}

class _FakeProcess implements Process {
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

class _StubHelperSignatureProbe implements IHelperSignatureProbe {
  const _StubHelperSignatureProbe(this._status);
  final HelperSignatureStatus _status;

  @override
  Future<HelperSignatureStatus> probe(String filePath) async => _status;
}

class _NeverCompletingHttpClient implements HttpClient {
  @override
  Duration? connectionTimeout;

  bool closedWithForce = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    return Completer<HttpClientRequest>().future;
  }

  @override
  void close({bool force = false}) {
    closedWithForce = closedWithForce || force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
