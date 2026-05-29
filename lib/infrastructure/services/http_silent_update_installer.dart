import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/application/services/silent_update_failure.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/security/helper_signature_probe.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';
import 'package:win32/win32.dart' as win32;

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
typedef DiskFreeSpaceResolver = Future<int?> Function(String directoryPath);

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
    IHelperSignatureProbe? helperSignatureProbe,
    DiskFreeSpaceResolver? diskFreeSpaceResolver,
    Duration downloadTimeout = _defaultDownloadTimeout,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _processStarter = processStarter ?? Process.start,
       _downloadDirectoryResolver = downloadDirectoryResolver ?? _resolveDefaultDownloadDirectory,
       _installDirectoryResolver = installDirectoryResolver ?? _resolveDefaultInstallDirectory,
       _installDirectoryWritableProbe = installDirectoryWritableProbe ?? _canWriteToInstallDirectory,
       _updateHelperPathResolver = updateHelperPathResolver ?? _resolveDefaultUpdateHelperPath,
       _currentProcessIdResolver = currentProcessIdResolver ?? _resolveCurrentProcessId,
       _updateDirectorySecurityHardener = updateDirectorySecurityHardener ?? _hardenUpdateDirectoryBestEffort,
       _helperSignatureProbe = helperSignatureProbe ?? PowerShellHelperSignatureProbe(),
       _diskFreeSpaceResolver = diskFreeSpaceResolver ?? _resolveDefaultDiskFreeSpace,
       _downloadTimeout = downloadTimeout;

  final HttpClientFactory _httpClientFactory;
  final SilentUpdateProcessStarter _processStarter;
  final Future<String> Function() _downloadDirectoryResolver;
  final InstallDirectoryResolver _installDirectoryResolver;
  final InstallDirectoryWritableProbe _installDirectoryWritableProbe;
  final UpdateHelperPathResolver _updateHelperPathResolver;
  final CurrentProcessIdResolver _currentProcessIdResolver;
  final UpdateDirectorySecurityHardener _updateDirectorySecurityHardener;
  final IHelperSignatureProbe _helperSignatureProbe;
  final DiskFreeSpaceResolver _diskFreeSpaceResolver;
  final Duration _downloadTimeout;

  /// Multiplier used to budget free space relative to the asset size. The
  /// install path writes the `.part`, renames to `.exe`, and the helper
  /// later runs the setup which extracts its payload — a 2x headroom keeps
  /// rare cases (chunky filesystem, AV temp files) from running out of
  /// space mid-install.
  static const int _diskSpaceBudgetMultiplier = 2;

  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
  static const int _waitPidTimeoutSeconds = 45;
  static const Duration _defaultDownloadTimeout = Duration(minutes: 5);
  static const Duration _icaclsTimeout = Duration(seconds: 30);
  static const Duration _cancelPollInterval = Duration(milliseconds: 100);

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

    // Pre-flight: refuse to start when the filesystem cannot hold the
    // download plus headroom. Bubbles a clear ValidationFailure instead of
    // letting the stream blow up half-way with a generic FileSystemException.
    final requiredBytes = request.assetSize * _diskSpaceBudgetMultiplier;
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
    final resumeEnabled = request.allowDownloadResume;
    // Set to true only when a transient transport error leaves a usable
    // partial behind; in that case the `finally` keeps the `.part` so the
    // next attempt can resume via Range instead of re-downloading the whole
    // installer. Every other exit (success, validation/hash mismatch,
    // cancellation) wipes it.
    var preservePartForResume = false;
    try {
      // When resume is on we keep the .part across retries; the _download
      // helper inspects it to decide between Range and full restart. When
      // resume is off we always start fresh to preserve the pre-existing
      // contract (each install attempt downloads the whole file).
      if (!resumeEnabled && partFile.existsSync()) {
        partFile.deleteSync();
      }

      final downloadResult = await _download(
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
        preservePartForResume = resumeEnabled && _isResumableDownloadError(downloadError!);
        return Failure<SilentUpdateInstallResult, Exception>(downloadError!);
      }

      if (request.cancelRequested?.call() ?? false) {
        _deleteIfExists(partFile);
        return _cancelledFailure(request.version);
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

      final actualSha256 = await _sha256OfStreaming(partFile);
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

      if (request.cancelRequested?.call() ?? false) {
        _deleteIfExists(installerFile);
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
      // Probe the source helper's Authenticode signature *before* copying
      // it to the updates directory, so a tampered helper is rejected on
      // the install path rather than caught by Windows later. Probe is
      // cached per session in the implementation so repeated checks within
      // a single process cost nothing after the first.
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
      final helperSha256 = await _sha256OfFileBestEffort(installedHelperFile);

      if (request.cancelRequested?.call() ?? false) {
        _deleteIfExists(launcherFile);
        _deleteIfExists(installerFile);
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
        _deleteIfExists(partFile);
      }
    }
  }

  /// A `.part` is only worth keeping for a follow-up resume when the failure
  /// was a transient transport error (timeout, dropped connection, 5xx, etc.,
  /// all mapped to [domain.NetworkFailure]). Validation failures (size/hash
  /// mismatch, appcast length overrun) mean the bytes on disk are poisoned,
  /// and cancellations are explicit user intent — both must wipe the partial
  /// so the next attempt starts clean.
  static bool _isResumableDownloadError(Exception error) {
    if (error is SilentInstallCancellationFailure) {
      return false;
    }
    return error is domain.NetworkFailure;
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

    // Defense-in-depth against TOCTOU: the staged helper lives in the updates
    // directory, where the current user keeps Modify rights so the agent can
    // write there. `install()` only verified the *source* helper before
    // copying it; by the time apply runs (user click or shutdown, possibly
    // long after the download) a same-user process could have swapped the
    // copy. Re-probe the *copied* helper's Authenticode right before launch so
    // a tampered binary cannot be handed to the elevation prompt.
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

  Future<Result<void>> _download(
    Uri assetUri,
    File destination, {
    required int expectedSize,
    required String version,
    required bool resume,
    bool Function()? cancelRequested,
  }) async {
    if (cancelRequested?.call() ?? false) {
      return _cancelledDownloadFailure(assetUri, version);
    }

    // Compute the resume offset *before* opening the network connection.
    // We delete any .part that already looks bigger than expected — the
    // SHA validation downstream would fail anyway, and a smaller restart
    // is cheaper than detecting a poisoned cache later.
    var startOffset = 0;
    if (resume && destination.existsSync()) {
      final existing = destination.lengthSync();
      if (existing > 0 && existing < expectedSize) {
        startOffset = existing;
      } else if (existing >= expectedSize) {
        destination.deleteSync();
      }
    }

    final client = _httpClientFactory();
    client.connectionTimeout = _downloadTimeout;
    var didTimeOut = false;
    var didCancel = false;
    final timeoutTimer = Timer(_downloadTimeout, () {
      didTimeOut = true;
      client.close(force: true);
    });
    // Poll the cancel token even when the response stream is blocked waiting
    // for more bytes. Without this, a slow server keeps `await for` parked
    // and cancellation only triggers between chunks.
    Timer? cancelPollTimer;
    if (cancelRequested != null) {
      cancelPollTimer = Timer.periodic(_cancelPollInterval, (_) {
        if (cancelRequested.call()) {
          didCancel = true;
          client.close(force: true);
        }
      });
    }
    try {
      final request = await client.getUrl(assetUri).timeout(_downloadTimeout);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      if (startOffset > 0) {
        // RFC 7233: open-ended range starts from the offset; server responds
        // 206 + Content-Range. A server that ignores Range either returns
        // 200 (full body) — handled below by restarting from zero — or
        // breaks contract (rare). We do not request a specific upper bound
        // to leave the server free to send the rest in one stream.
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$startOffset-');
      }
      final response = await request.close().timeout(_downloadTimeout);
      if (cancelRequested?.call() ?? false) {
        didCancel = true;
        client.close(force: true);
        return _cancelledDownloadFailure(assetUri, version);
      }
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

      // If we asked for Range and server ignored it (200 + full body),
      // start from zero by truncating the .part. Without this, the cached
      // bytes would prepend the freshly-streamed full file.
      var effectiveStartOffset = startOffset;
      final acceptedResume = response.statusCode == 206;
      if (startOffset > 0 && !acceptedResume) {
        effectiveStartOffset = 0;
        if (destination.existsSync()) {
          destination.deleteSync();
        }
      }

      // For partial responses, content-length is the remainder; total must
      // not exceed the expected size when added to the offset.
      final reported = response.contentLength;
      if (reported > 0 && effectiveStartOffset + reported > expectedSize) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Silent update asset download exceeded appcast length',
            context: <String, dynamic>{
              'operation': 'silentUpdateDownload',
              'version': version,
              'expected_size': expectedSize,
              'content_length': reported,
              'start_offset': effectiveStartOffset,
              'asset_url': assetUri.toString(),
            },
          ),
        );
      }

      // Append when resuming (206) or truncate otherwise. `openWrite`
      // defaults to `FileMode.write` (truncate); `append` keeps existing
      // bytes intact.
      final sink = effectiveStartOffset > 0 ? destination.openWrite(mode: FileMode.append) : destination.openWrite();
      try {
        var downloadedBytes = effectiveStartOffset;
        await for (final chunk in response) {
          if (cancelRequested?.call() ?? false) {
            didCancel = true;
            client.close(force: true);
            break;
          }
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
      if (didCancel) {
        return _cancelledDownloadFailure(assetUri, version);
      }
      return const Success(unit);
    } on TimeoutException catch (error) {
      didTimeOut = true;
      client.close(force: true);
      return _downloadTimeoutFailure(assetUri, error);
    } on Exception catch (error) {
      if (didCancel) {
        return _cancelledDownloadFailure(assetUri, version);
      }
      if (didTimeOut) {
        return _downloadTimeoutFailure(assetUri, error);
      }
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
      timeoutTimer.cancel();
      cancelPollTimer?.cancel();
      client.close(force: true);
    }
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

  Result<void> _cancelledDownloadFailure(Uri assetUri, String version) {
    return Failure(
      SilentInstallCancellationFailure(
        message: 'Silent update download cancelled before completion',
        context: <String, dynamic>{
          'operation': 'silentUpdateDownload',
          'asset_url': assetUri.toString(),
          'version': version,
        },
      ),
    );
  }

  Result<void> _downloadTimeoutFailure(
    Uri assetUri,
    Exception error,
  ) {
    return Failure(
      domain.NetworkFailure.withContext(
        message: 'Silent update asset download timed out',
        cause: error,
        context: <String, dynamic>{
          'operation': 'silentUpdateDownload',
          'asset_url': assetUri.toString(),
          'timeout_ms': _downloadTimeout.inMilliseconds,
        },
      ),
    );
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

  /// Resolves free disk space on the volume that hosts [directoryPath].
  ///
  /// On Windows uses `GetDiskFreeSpaceExW` via FFI; on other platforms or
  /// when the syscall fails returns `null` so the installer falls back to
  /// best-effort (skips the check). Returning `null` is intentionally
  /// distinct from `0` so a real "no space" answer can still block.
  static Future<int?> _resolveDefaultDiskFreeSpace(String directoryPath) async {
    if (!Platform.isWindows) return null;
    final pathPtr = directoryPath.toNativeUtf16();
    final freeBytesAvailable = calloc<Uint64>();
    final totalNumberOfBytes = calloc<Uint64>();
    final totalNumberOfFreeBytes = calloc<Uint64>();
    try {
      final ok = win32.GetDiskFreeSpaceEx(
        pathPtr,
        freeBytesAvailable.cast(),
        totalNumberOfBytes.cast(),
        totalNumberOfFreeBytes.cast(),
      );
      if (ok == 0) return null;
      // FreeBytesAvailable reports the space available to the caller's
      // quota (preferred when ACLs limit the process), falling back to
      // total free when zero (rare).
      final available = freeBytesAvailable.value;
      if (available > 0) return available;
      final totalFree = totalNumberOfFreeBytes.value;
      return totalFree > 0 ? totalFree : 0;
    } on Object {
      return null;
    } finally {
      calloc.free(pathPtr);
      calloc.free(freeBytesAvailable);
      calloc.free(totalNumberOfBytes);
      calloc.free(totalNumberOfFreeBytes);
    }
  }

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
      ).timeout(_icaclsTimeout);
      return result.exitCode == 0 ? 'restricted' : 'failed:${result.exitCode}';
    } on TimeoutException {
      return 'failedTimeout';
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

  /// Streams the file through SHA-256 instead of loading every byte
  /// into memory. Matters because installer payloads keep growing
  /// (runtime + bundled dependencies) and `readAsBytesSync` would
  /// allocate the whole thing on the heap *and* block the event loop.
  static Future<String> _sha256OfStreaming(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Same as [_sha256OfStreaming] but never throws — used for diagnostic
  /// fingerprints where measurement failure must not abort the install
  /// pipeline.
  static Future<String?> _sha256OfFileBestEffort(File file) async {
    try {
      return await _sha256OfStreaming(file);
    } on FileSystemException {
      return null;
    } on Exception {
      return null;
    }
  }

  static void _deleteIfExists(File file) {
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
