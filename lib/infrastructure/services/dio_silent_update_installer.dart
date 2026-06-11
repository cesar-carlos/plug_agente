import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/security/helper_signature_probe.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/errors/silent_install_failure.dart';
import 'package:plug_agente/domain/services/silent_update_installer.dart';
import 'package:plug_agente/infrastructure/services/silent_update_installer_download.dart';
import 'package:plug_agente/infrastructure/services/silent_update_installer_file_ops.dart';
import 'package:plug_agente/infrastructure/services/silent_update_installer_platform.dart';
import 'package:plug_agente/infrastructure/services/silent_update_installer_types.dart';
import 'package:result_dart/result_dart.dart';

export 'silent_update_installer_types.dart';

/// Silent update installer that downloads assets via [Dio] per project stack rules.
class DioSilentUpdateInstaller implements ISilentUpdateInstaller {
  DioSilentUpdateInstaller({
    DioFactoryFn? dioFactory,
    @Deprecated('Use dioFactory instead') HttpClientFactory? httpClientFactory,
    SilentUpdateProcessStarter? processStarter,
    Future<String> Function()? downloadDirectoryResolver,
    InstallDirectoryResolver? installDirectoryResolver,
    InstallDirectoryWritableProbe? installDirectoryWritableProbe,
    UpdateHelperPathResolver? updateHelperPathResolver,
    CurrentProcessIdResolver? currentProcessIdResolver,
    UpdateDirectorySecurityHardener? updateDirectorySecurityHardener,
    IHelperSignatureProbe? helperSignatureProbe,
    DiskFreeSpaceResolver? diskFreeSpaceResolver,
    Duration downloadTimeout = _defaultDownloadTimeout,
  }) : _processStarter = processStarter ?? Process.start,
       _downloadDirectoryResolver =
           downloadDirectoryResolver ?? SilentUpdateInstallerPlatform.resolveDefaultDownloadDirectory,
       _installDirectoryResolver =
           installDirectoryResolver ?? SilentUpdateInstallerPlatform.resolveDefaultInstallDirectory,
       _installDirectoryWritableProbe =
           installDirectoryWritableProbe ?? SilentUpdateInstallerPlatform.canWriteToInstallDirectory,
       _updateHelperPathResolver =
           updateHelperPathResolver ?? SilentUpdateInstallerPlatform.resolveDefaultUpdateHelperPath,
       _currentProcessIdResolver = currentProcessIdResolver ?? SilentUpdateInstallerPlatform.resolveCurrentProcessId,
       _updateDirectorySecurityHardener =
           updateDirectorySecurityHardener ?? SilentUpdateInstallerPlatform.hardenUpdateDirectoryBestEffort,
       _helperSignatureProbe = helperSignatureProbe ?? PowerShellHelperSignatureProbe(),
       _diskFreeSpaceResolver = diskFreeSpaceResolver ?? SilentUpdateInstallerPlatform.resolveDefaultDiskFreeSpace,
       _downloader = SilentUpdateInstallerDownload(
         dioFactory:
             dioFactory ??
             (httpClientFactory != null
                 ? () {
                     final dio = Dio(
                       BaseOptions(
                         receiveTimeout: downloadTimeout,
                         sendTimeout: downloadTimeout,
                       ),
                     );
                     dio.httpClientAdapter = IOHttpClientAdapter(
                       createHttpClient: httpClientFactory,
                     );
                     return dio;
                   }
                 : () => _createPlainDio(downloadTimeout)),
         downloadTimeout: downloadTimeout,
       );

  final SilentUpdateProcessStarter _processStarter;
  final Future<String> Function() _downloadDirectoryResolver;
  final InstallDirectoryResolver _installDirectoryResolver;
  final InstallDirectoryWritableProbe _installDirectoryWritableProbe;
  final UpdateHelperPathResolver _updateHelperPathResolver;
  final CurrentProcessIdResolver _currentProcessIdResolver;
  final UpdateDirectorySecurityHardener _updateDirectorySecurityHardener;
  final IHelperSignatureProbe _helperSignatureProbe;
  final DiskFreeSpaceResolver _diskFreeSpaceResolver;
  final SilentUpdateInstallerDownload _downloader;

  /// Multiplier used to budget free space relative to the asset size. The
  /// install path writes the `.part`, renames to `.exe`, and the helper
  /// later runs the setup which extracts its payload — a 2x headroom keeps
  /// rare cases (chunky filesystem, AV temp files) from running out of
  /// space mid-install.
  static const int diskSpaceBudgetMultiplier = 2;

  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
  static const int _waitPidTimeoutSeconds = 45;
  static const Duration _defaultDownloadTimeout = Duration(minutes: 5);

  static Dio _createPlainDio(Duration timeout) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient()..autoUncompress = true,
    );
    return dio;
  }

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
    if (assetUri == null || !isAutoUpdateInstallerUrl(request.assetUrl)) {
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

    if (request.cancelRequested?.call() ?? false) {
      return _cancelledFailure(request.version);
    }

    final downloadDirectoryPath = await _downloadDirectoryResolver();
    final downloadDirectory = Directory(downloadDirectoryPath);
    await downloadDirectory.create(recursive: true);

    final requiredBytes = request.assetSize * diskSpaceBudgetMultiplier;
    final freeBytes = await _diskFreeSpaceResolver(downloadDirectory.path);
    if (freeBytes != null && freeBytes < requiredBytes) {
      return Failure<SilentUpdateInstallResult, Exception>(
        domain.ValidationFailure.withContext(
          message:
              'Silent update aborted: download directory has insufficient free space '
              '(need at least $requiredBytes bytes, $freeBytes available).',
          context: <String, dynamic>{
            'operation': 'silentUpdateInstall',
            'validation_code': 'insufficient_disk_space',
            'version': request.version,
            'download_directory': downloadDirectory.path,
            'required_bytes': requiredBytes,
            'free_bytes': freeBytes,
            'asset_size': request.assetSize,
          },
        ),
      );
    }

    final updateDirectorySecurityStatus = await _updateDirectorySecurityHardener(downloadDirectory.path);

    final installerName = SilentUpdateInstallerFileOps.sanitizeFileName(
      request.assetName.isNotEmpty ? request.assetName : p.basename(assetUri.path),
    );
    final installerPath = p.join(downloadDirectory.path, installerName);
    final partPath = '$installerPath.part';
    final logPath = p.join(
      downloadDirectory.path,
      'PlugAgente-Update-${SilentUpdateInstallerFileOps.sanitizeFileName(request.version)}.log',
    );
    final launcherPath = p.join(
      downloadDirectory.path,
      'PlugAgente-Update-Helper-${SilentUpdateInstallerFileOps.sanitizeFileName(request.version)}.exe',
    );
    final launcherStatusPath = p.join(
      downloadDirectory.path,
      'PlugAgente-Update-Helper-${SilentUpdateInstallerFileOps.sanitizeFileName(request.version)}.status.json',
    );

    final partFile = File(partPath);
    final resumeEnabled = request.allowDownloadResume;
    var preservePartForResume = false;
    try {
      if (!resumeEnabled && partFile.existsSync()) {
        partFile.deleteSync();
      }

      final downloadResult = await _downloader.download(
        assetUri,
        partFile,
        expectedSize: request.assetSize,
        version: request.version,
        resume: resumeEnabled,
        cancelRequested: request.cancelRequested,
      );
      Exception? downloadError;
      downloadResult.fold(
        (_) {},
        (error) => downloadError = error,
      );
      if (downloadError != null) {
        preservePartForResume =
            resumeEnabled && SilentUpdateInstallerDownload.isResumableDownloadError(downloadError!);
        return Failure<SilentUpdateInstallResult, Exception>(downloadError!);
      }

      if (request.cancelRequested?.call() ?? false) {
        SilentUpdateInstallerFileOps.deleteIfExists(partFile);
        return _cancelledFailure(request.version);
      }

      final actualSize = partFile.lengthSync();
      if (actualSize != request.assetSize) {
        SilentUpdateInstallerFileOps.deleteIfExists(partFile);
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

      final actualSha256 = await SilentUpdateInstallerFileOps.sha256OfStreaming(partFile);
      if (actualSha256 != sha256Value) {
        SilentUpdateInstallerFileOps.deleteIfExists(partFile);
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

      if (request.cancelRequested?.call() ?? false) {
        SilentUpdateInstallerFileOps.deleteIfExists(installerFile);
        return _cancelledFailure(request.version);
      }

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
      final helperSignatureStatus = await _helperSignatureProbe.probe(installedHelperPath);
      if (request.requireValidSignature && helperSignatureStatus != HelperSignatureStatus.valid) {
        return Failure<SilentUpdateInstallResult, Exception>(
          domain.ValidationFailure.withContext(
            message:
                'Silent update helper signature is required but reported '
                '${helperSignatureStatus.name}. Refusing to launch.',
            context: <String, dynamic>{
              'operation': 'silentUpdateInstall',
              'version': request.version,
              'helper_path': installedHelperPath,
              'helper_signature_status': helperSignatureStatus.name,
              'validation_code': 'helper_signature_${helperSignatureStatus.name}',
            },
          ),
        );
      }

      installedHelperFile.copySync(launcherPath);
      final appPid = _currentProcessIdResolver();
      final helperSha256 = await SilentUpdateInstallerFileOps.sha256OfFileBestEffort(installedHelperFile);

      if (request.cancelRequested?.call() ?? false) {
        SilentUpdateInstallerFileOps.deleteIfExists(launcherFile);
        SilentUpdateInstallerFileOps.deleteIfExists(installerFile);
        return _cancelledFailure(request.version);
      }

      if (!request.deferHelperLaunch) {
        await _startHelperProcess(
          launcherPath: launcherPath,
          installerPath: installerPath,
          installDirectory: installDirectory,
          logPath: logPath,
          launcherStatusPath: launcherStatusPath,
          appPid: appPid,
          assetSize: request.assetSize,
          sha256Value: sha256Value,
          installDirectoryWritable: installDirectoryWritable,
          requireValidSignature: request.requireValidSignature,
          version: request.version,
        );
      }

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
          helperSha256: helperSha256,
          helperSignatureStatus: helperSignatureStatus.name,
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
      if (!preservePartForResume) {
        SilentUpdateInstallerFileOps.deleteIfExists(partFile);
      }
    }
  }

  @override
  Future<Result<void>> launchPreparedHelper(
    SilentUpdateLaunchRequest request,
  ) async {
    final installerFile = File(request.installerPath);
    final launcherFile = File(request.launcherPath);
    if (!installerFile.existsSync() || !launcherFile.existsSync()) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Silent update artifacts are no longer available on disk',
          context: <String, dynamic>{
            'operation': 'silentUpdateLaunchHelper',
            'version': request.version,
            'installer_path': request.installerPath,
            'launcher_path': request.launcherPath,
            'validation_code': 'prepared_helper_missing',
          },
        ),
      );
    }

    if (request.requireValidSignature) {
      final launcherSignatureStatus = await _helperSignatureProbe.probe(request.launcherPath);
      if (launcherSignatureStatus != HelperSignatureStatus.valid) {
        return Failure(
          domain.ValidationFailure.withContext(
            message:
                'Prepared silent update helper signature is required but reported '
                '${launcherSignatureStatus.name}. Refusing to launch.',
            context: <String, dynamic>{
              'operation': 'silentUpdateLaunchHelper',
              'version': request.version,
              'launcher_path': request.launcherPath,
              'helper_signature_status': launcherSignatureStatus.name,
              'validation_code': 'helper_signature_${launcherSignatureStatus.name}',
            },
          ),
        );
      }
    }

    try {
      await _startHelperProcess(
        launcherPath: request.launcherPath,
        installerPath: request.installerPath,
        installDirectory: request.installDirectory,
        logPath: request.logPath,
        launcherStatusPath: request.launcherStatusPath,
        appPid: request.appPid,
        assetSize: request.assetSize,
        sha256Value: request.sha256.toLowerCase(),
        installDirectoryWritable: request.installDirectoryWritable,
        requireValidSignature: request.requireValidSignature,
        version: request.version,
      );
      return const Success(unit);
    } on Exception catch (error) {
      return Failure(
        domain.ServerFailure.withContext(
          message: 'Failed to launch silent update helper',
          cause: error,
          context: <String, dynamic>{
            'operation': 'silentUpdateLaunchHelper',
            'version': request.version,
            'launcher_path': request.launcherPath,
          },
        ),
      );
    }
  }

  Future<void> _startHelperProcess({
    required String launcherPath,
    required String installerPath,
    required String installDirectory,
    required String logPath,
    required String launcherStatusPath,
    required int appPid,
    required int assetSize,
    required String sha256Value,
    required bool installDirectoryWritable,
    required bool requireValidSignature,
    required String version,
  }) async {
    await _processStarter(
      launcherPath,
      <String>[
        '--version',
        version,
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
        assetSize.toString(),
        '--sha256',
        sha256Value,
        '--try-current-user-first=$installDirectoryWritable',
        '--require-valid-signature=$requireValidSignature',
        '--wait-pid-timeout-seconds',
        _waitPidTimeoutSeconds.toString(),
      ],
      mode: ProcessStartMode.detached,
    );
  }

  Result<SilentUpdateInstallResult> _cancelledFailure(String version) {
    return Failure<SilentUpdateInstallResult, Exception>(
      SilentInstallCancellationFailure(
        message: 'Silent update cancelled before completion',
        context: <String, dynamic>{
          'operation': 'silentUpdateInstall',
          'version': version,
        },
      ),
    );
  }

  @override
  Future<Result<void>> cleanupObsoleteArtifacts() async {
    try {
      final downloadDirectory = Directory(await _downloadDirectoryResolver());
      if (!downloadDirectory.existsSync()) {
        return const Success(unit);
      }
      SilentUpdateInstallerFileOps.cleanupFamily(
        downloadDirectory,
        prefix: 'PlugAgente-Setup-',
        keepLatestCount: 3,
        maxAge: const Duration(days: 30),
      );
      SilentUpdateInstallerFileOps.cleanupFamily(
        downloadDirectory,
        prefix: 'PlugAgente-Update-Helper-',
        keepLatestCount: 3,
        maxAge: const Duration(days: 30),
      );
      SilentUpdateInstallerFileOps.cleanupFamily(
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
}

/// Backward-compatible alias kept for existing tests and imports.
typedef HttpSilentUpdateInstaller = DioSilentUpdateInstaller;
