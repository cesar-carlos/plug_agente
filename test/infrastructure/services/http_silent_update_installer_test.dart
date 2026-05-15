import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/application/services/silent_update_installer.dart';
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
