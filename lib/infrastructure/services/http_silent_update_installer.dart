import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

typedef HttpClientFactory = HttpClient Function();
typedef SilentUpdateProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      ProcessStartMode mode,
    });
typedef InstallDirectoryResolver = Future<String> Function();
typedef InstallDirectoryWritableProbe = Future<bool> Function(String installDirectory);
typedef UpdateHelperPathResolver = Future<String> Function();
typedef CurrentProcessIdResolver = int Function();
typedef UpdateDirectorySecurityHardener = Future<String> Function(String updateDirectory);

class HttpSilentUpdateInstaller implements ISilentUpdateInstaller {
  HttpSilentUpdateInstaller({
    HttpClientFactory? httpClientFactory,
    SilentUpdateProcessStarter? processStarter,
    Future<String> Function()? downloadDirectoryResolver,
    InstallDirectoryResolver? installDirectoryResolver,
    InstallDirectoryWritableProbe? installDirectoryWritableProbe,
    UpdateHelperPathResolver? updateHelperPathResolver,
    CurrentProcessIdResolver? currentProcessIdResolver,
    UpdateDirectorySecurityHardener? updateDirectorySecurityHardener,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _processStarter = processStarter ?? Process.start,
       _downloadDirectoryResolver = downloadDirectoryResolver ?? _resolveDefaultDownloadDirectory,
       _installDirectoryResolver = installDirectoryResolver ?? _resolveDefaultInstallDirectory,
       _installDirectoryWritableProbe = installDirectoryWritableProbe ?? _canWriteToInstallDirectory,
       _updateHelperPathResolver = updateHelperPathResolver ?? _resolveDefaultUpdateHelperPath,
       _currentProcessIdResolver = currentProcessIdResolver ?? _resolveCurrentProcessId,
       _updateDirectorySecurityHardener = updateDirectorySecurityHardener ?? _hardenUpdateDirectoryBestEffort;

  final HttpClientFactory _httpClientFactory;
  final SilentUpdateProcessStarter _processStarter;
  final Future<String> Function() _downloadDirectoryResolver;
  final InstallDirectoryResolver _installDirectoryResolver;
  final InstallDirectoryWritableProbe _installDirectoryWritableProbe;
  final UpdateHelperPathResolver _updateHelperPathResolver;
  final CurrentProcessIdResolver _currentProcessIdResolver;
  final UpdateDirectorySecurityHardener _updateDirectorySecurityHardener;

  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
  static const int _waitPidTimeoutSeconds = 45;

  @override
  Future<Result<SilentUpdateInstallResult>> install(
    SilentUpdateInstallRequest request,
  ) async {
    final sha256Value = request.sha256.trim().toLowerCase();
    if (!_sha256Pattern.hasMatch(sha256Value)) {
      return Failure<SilentUpdateInstallResult, Exception>(
        domain.ValidationFailure.withContext(
          message: 'Silent update asset SHA-256 is missing or invalid',
          context: <String, dynamic>{
            'operation': 'silentUpdateInstall',
            'version': request.version,
          },
        ),
      );
    }

    final assetUri = Uri.tryParse(request.assetUrl);
    if (assetUri == null || !assetUri.hasScheme || !assetUri.hasAuthority) {
      return Failure<SilentUpdateInstallResult, Exception>(
        domain.ValidationFailure.withContext(
          message: 'Silent update asset URL is invalid',
          context: <String, dynamic>{
            'operation': 'silentUpdateInstall',
            'version': request.version,
            'asset_url': request.assetUrl,
          },
        ),
      );
    }

    final downloadDirectoryPath = await _downloadDirectoryResolver();
    final downloadDirectory = Directory(downloadDirectoryPath);
    await downloadDirectory.create(recursive: true);
    final updateDirectorySecurityStatus = await _updateDirectorySecurityHardener(downloadDirectory.path);

    final installerName = _sanitizeFileName(
      request.assetName.isNotEmpty ? request.assetName : p.basename(assetUri.path),
    );
    final installerPath = p.join(downloadDirectory.path, installerName);
    final partPath = '$installerPath.part';
    final logPath = p.join(
      downloadDirectory.path,
      'PlugAgente-Update-${_sanitizeFileName(request.version)}.log',
    );
    final launcherPath = p.join(
      downloadDirectory.path,
      'PlugAgente-Update-Helper-${_sanitizeFileName(request.version)}.exe',
    );
    final launcherStatusPath = p.join(
      downloadDirectory.path,
      'PlugAgente-Update-Helper-${_sanitizeFileName(request.version)}.status.json',
    );

    final partFile = File(partPath);
    try {
      if (partFile.existsSync()) {
        partFile.deleteSync();
      }

      final downloadResult = await _download(
        assetUri,
        partFile,
        expectedSize: request.assetSize,
        version: request.version,
      );
      Exception? downloadError;
      downloadResult.fold(
        (_) {},
        (error) => downloadError = error,
      );
      if (downloadError != null) {
        return Failure<SilentUpdateInstallResult, Exception>(downloadError!);
      }

      final actualSize = partFile.lengthSync();
      if (actualSize != request.assetSize) {
        _deleteIfExists(partFile);
        return Failure<SilentUpdateInstallResult, Exception>(
          domain.ValidationFailure.withContext(
            message: 'Silent update asset size does not match appcast length',
            context: <String, dynamic>{
              'operation': 'silentUpdateInstall',
              'version': request.version,
              'expected_size': request.assetSize,
              'actual_size': actualSize,
            },
          ),
        );
      }

      final actualSha256 = _sha256Of(partFile);
      if (actualSha256 != sha256Value) {
        _deleteIfExists(partFile);
        return Failure<SilentUpdateInstallResult, Exception>(
          domain.ValidationFailure.withContext(
            message: 'Silent update asset SHA-256 does not match appcast digest',
            context: <String, dynamic>{
              'operation': 'silentUpdateInstall',
              'version': request.version,
              'expected_sha256': sha256Value,
              'actual_sha256': actualSha256,
            },
          ),
        );
      }

      final installerFile = File(installerPath);
      if (installerFile.existsSync()) {
        installerFile.deleteSync();
      }
      partFile.renameSync(installerPath);

      final installDirectory = await _installDirectoryResolver();
      final installDirectoryWritable = await _installDirectoryWritableProbe(installDirectory);
      final strategy = installDirectoryWritable
          ? SilentUpdateInstallStrategy.currentUserThenElevated
          : SilentUpdateInstallStrategy.elevatedOnly;
      final installedHelperPath = await _updateHelperPathResolver();
      final installedHelperFile = File(installedHelperPath);
      if (!installedHelperFile.existsSync()) {
        return Failure<SilentUpdateInstallResult, Exception>(
          domain.ServerFailure.withContext(
            message: 'Silent update helper is not available',
            context: <String, dynamic>{
              'operation': 'silentUpdateInstall',
              'version': request.version,
              'helper_path': installedHelperPath,
            },
          ),
        );
      }
      final launcherFile = File(launcherPath);
      if (launcherFile.existsSync()) {
        launcherFile.deleteSync();
      }
      installedHelperFile.copySync(launcherPath);
      final appPid = _currentProcessIdResolver();

      await _processStarter(
        launcherPath,
        <String>[
          '--version',
          request.version,
          '--installer',
          installerPath,
          '--install-dir',
          installDirectory,
          '--log',
          logPath,
          '--status',
          launcherStatusPath,
          '--app-pid',
          appPid.toString(),
          '--asset-size',
          request.assetSize.toString(),
          '--sha256',
          sha256Value,
          '--try-current-user-first=$installDirectoryWritable',
          '--require-valid-signature=${request.requireValidSignature}',
          '--wait-pid-timeout-seconds',
          _waitPidTimeoutSeconds.toString(),
        ],
        mode: ProcessStartMode.detached,
      );

      return Success<SilentUpdateInstallResult, Exception>(
        SilentUpdateInstallResult(
          installerPath: installerPath,
          logPath: logPath,
          launcherPath: launcherPath,
          launcherStatusPath: launcherStatusPath,
          installDirectory: installDirectory,
          strategy: strategy,
          installDirectoryWritable: installDirectoryWritable,
          appPid: appPid,
          updateDirectorySecurityStatus: updateDirectorySecurityStatus,
        ),
      );
    } on Exception catch (error) {
      return Failure<SilentUpdateInstallResult, Exception>(
        domain.ServerFailure.withContext(
          message: 'Failed to start silent update installer',
          cause: error,
          context: <String, dynamic>{
            'operation': 'silentUpdateInstall',
            'version': request.version,
            'asset_url': request.assetUrl,
            'installer_path': installerPath,
            'launcher_path': launcherPath,
          },
        ),
      );
    } finally {
      _deleteIfExists(partFile);
    }
  }

  Future<Result<void>> _download(
    Uri assetUri,
    File destination, {
    required int expectedSize,
    required String version,
  }) async {
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(assetUri);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return Failure(
          domain.NetworkFailure.withContext(
            message: 'Silent update asset download failed',
            context: <String, dynamic>{
              'operation': 'silentUpdateDownload',
              'status_code': response.statusCode,
              'asset_url': assetUri.toString(),
            },
          ),
        );
      }

      if (response.contentLength > expectedSize) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Silent update asset download exceeded appcast length',
            context: <String, dynamic>{
              'operation': 'silentUpdateDownload',
              'version': version,
              'expected_size': expectedSize,
              'content_length': response.contentLength,
              'asset_url': assetUri.toString(),
            },
          ),
        );
      }

      final sink = destination.openWrite();
      try {
        var downloadedBytes = 0;
        await for (final chunk in response) {
          downloadedBytes += chunk.length;
          if (downloadedBytes > expectedSize) {
            return Failure(
              domain.ValidationFailure.withContext(
                message: 'Silent update asset download exceeded appcast length',
                context: <String, dynamic>{
                  'operation': 'silentUpdateDownload',
                  'version': version,
                  'expected_size': expectedSize,
                  'downloaded_size': downloadedBytes,
                  'asset_url': assetUri.toString(),
                },
              ),
            );
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Silent update asset download failed',
          cause: error,
          context: <String, dynamic>{
            'operation': 'silentUpdateDownload',
            'asset_url': assetUri.toString(),
          },
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _resolveDefaultDownloadDirectory() async {
    final context = await GlobalStoragePathResolver.resolveContext();
    return p.join(context.appDirectoryPath, 'updates');
  }

  static Future<String> _resolveDefaultInstallDirectory() async {
    return File(Platform.resolvedExecutable).parent.path;
  }

  static Future<String> _resolveDefaultUpdateHelperPath() async {
    return p.join(File(Platform.resolvedExecutable).parent.path, 'plug_update_helper.exe');
  }

  static int _resolveCurrentProcessId() => pid;

  static Future<String> _hardenUpdateDirectoryBestEffort(String updateDirectory) async {
    if (!Platform.isWindows) {
      return 'skippedNotWindows';
    }

    final programData = Platform.environment['ProgramData'] ?? Platform.environment['ALLUSERSPROFILE'];
    if (programData == null || programData.isEmpty) {
      return 'skippedNoProgramData';
    }
    final normalizedUpdateDirectory = p.normalize(updateDirectory).toLowerCase();
    final normalizedProgramData = p.normalize(programData).toLowerCase();
    if (!p.isWithin(normalizedProgramData, normalizedUpdateDirectory) &&
        normalizedUpdateDirectory != normalizedProgramData) {
      return 'skippedNonGlobalDirectory';
    }

    final username = Platform.environment['USERNAME']?.trim() ?? '';
    final userDomain = Platform.environment['USERDOMAIN']?.trim() ?? '';
    if (username.isEmpty) {
      return 'skippedNoUser';
    }
    final account = userDomain.isEmpty ? username : '$userDomain\\$username';

    try {
      final result = await Process.run(
        'icacls',
        <String>[
          updateDirectory,
          '/inheritance:r',
          '/grant:r',
          '*S-1-5-18:(OI)(CI)F',
          '*S-1-5-32-544:(OI)(CI)F',
          '$account:(OI)(CI)M',
        ],
      );
      return result.exitCode == 0 ? 'restricted' : 'failed:${result.exitCode}';
    } on ProcessException {
      return 'failedToStart';
    }
  }

  static Future<bool> _canWriteToInstallDirectory(String installDirectory) async {
    final probeFile = File(
      p.join(
        installDirectory,
        '.plug_agente_update_probe_${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      probeFile.writeAsStringSync('probe');
      probeFile.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<Result<void>> cleanupObsoleteArtifacts() async {
    try {
      final downloadDirectory = Directory(await _downloadDirectoryResolver());
      if (!downloadDirectory.existsSync()) {
        return const Success(unit);
      }
      _cleanupFamily(
        downloadDirectory,
        prefix: 'PlugAgente-Setup-',
        keepLatestCount: 3,
        maxAge: const Duration(days: 30),
      );
      _cleanupFamily(
        downloadDirectory,
        prefix: 'PlugAgente-Update-Helper-',
        keepLatestCount: 3,
        maxAge: const Duration(days: 30),
      );
      _cleanupFamily(
        downloadDirectory,
        prefix: 'PlugAgente-Update-',
        excludePrefix: 'PlugAgente-Update-Helper-',
        keepLatestCount: 3,
        maxAge: const Duration(days: 30),
      );
      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to clean obsolete silent update artifacts',
          cause: error,
          context: <String, dynamic>{'operation': 'silentUpdateCleanup'},
        ),
      );
    }
  }

  static void _cleanupFamily(
    Directory directory, {
    required String prefix,
    required int keepLatestCount,
    required Duration maxAge,
    String? excludePrefix,
  }) {
    final now = DateTime.now();
    final files = directory.listSync().whereType<File>().where((file) {
      final name = p.basename(file.path);
      return name.startsWith(prefix) && (excludePrefix == null || !name.startsWith(excludePrefix));
    }).toList()..sort((left, right) => right.lastModifiedSync().compareTo(left.lastModifiedSync()));
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final isOld = now.difference(file.lastModifiedSync()) > maxAge;
      if (index >= keepLatestCount || isOld) {
        _deleteIfExists(file);
      }
    }
  }

  static String _sanitizeFileName(String raw) {
    final sanitized = raw.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    if (sanitized.isEmpty) {
      return 'PlugAgente-Setup.exe';
    }
    return sanitized;
  }

  static String _sha256Of(File file) {
    final bytes = file.readAsBytesSync();
    return sha256.convert(bytes).toString();
  }

  static void _deleteIfExists(File file) {
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
