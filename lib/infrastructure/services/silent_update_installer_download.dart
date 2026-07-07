import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/errors/silent_install_failure.dart';
import 'package:plug_agente/infrastructure/services/silent_update_installer_types.dart';
import 'package:result_dart/result_dart.dart';

/// Dio-backed asset download for silent update installation.
final class SilentUpdateInstallerDownload {
  SilentUpdateInstallerDownload({
    required DioFactoryFn dioFactory,
    required Duration downloadTimeout,
    Duration cancelPollInterval = const Duration(milliseconds: 100),
  }) : _dioFactory = dioFactory,
       _downloadTimeout = downloadTimeout,
       _cancelPollInterval = cancelPollInterval;

  final DioFactoryFn _dioFactory;
  final Duration _downloadTimeout;
  final Duration _cancelPollInterval;

  /// A `.part` is only worth keeping for a follow-up resume when the failure
  /// was a transient transport error (timeout, dropped connection, 5xx, etc.,
  /// all mapped to [domain.NetworkFailure]). Validation failures (size/hash
  /// mismatch, appcast length overrun) mean the bytes on disk are poisoned,
  /// and cancellations are explicit user intent — both must wipe the partial
  /// so the next attempt starts clean.
  static bool isResumableDownloadError(Exception error) {
    if (error is SilentInstallCancellationFailure) {
      return false;
    }
    return error is domain.NetworkFailure;
  }

  Future<Result<void>> download(
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

    var startOffset = 0;
    if (resume && destination.existsSync()) {
      final existing = destination.lengthSync();
      if (existing > 0 && existing < expectedSize) {
        startOffset = existing;
      } else if (existing >= expectedSize) {
        destination.deleteSync();
      }
    }

    final dio = _dioFactory();
    dio.options.connectTimeout = _downloadTimeout;
    dio.options.receiveTimeout = _downloadTimeout;
    dio.options.sendTimeout = _downloadTimeout;
    var didTimeOut = false;
    var didCancel = false;

    // Stall watchdog, not a total-duration cap: rearmed every time data
    // actually arrives (response headers, then each body chunk below) so a
    // large installer downloading steadily over a slow-but-healthy
    // connection is never aborted just because the whole transfer takes
    // longer than `_downloadTimeout`. Only `_downloadTimeout` of silence
    // (no bytes at all) counts as a stall.
    Timer? stallTimer;
    void armStallTimer() {
      stallTimer?.cancel();
      stallTimer = Timer(_downloadTimeout, () {
        didTimeOut = true;
        didCancel = true;
        dio.close(force: true);
      });
    }

    armStallTimer();
    Timer? cancelPollTimer;
    if (cancelRequested != null) {
      cancelPollTimer = Timer.periodic(_cancelPollInterval, (_) {
        if (cancelRequested.call()) {
          didCancel = true;
          dio.close(force: true);
        }
      });
    }
    try {
      final headers = <String, String>{'Cache-Control': 'no-cache'};
      if (startOffset > 0) {
        headers['Range'] = 'bytes=$startOffset-';
      }
      final response = await dio
          .get<ResponseBody>(
            assetUri.toString(),
            options: Options(
              responseType: ResponseType.stream,
              connectTimeout: _downloadTimeout,
              receiveTimeout: _downloadTimeout,
              sendTimeout: _downloadTimeout,
              headers: headers,
            ),
          )
          .timeout(
            _downloadTimeout,
            onTimeout: () {
              didTimeOut = true;
              dio.close(force: true);
              throw TimeoutException('Silent update asset download timed out', _downloadTimeout);
            },
          );
      // Headers arrived, so the connection is alive; rearm the watchdog for
      // the body-streaming phase below instead of letting the timer keep
      // counting down from before the request even started.
      armStallTimer();
      if (cancelRequested?.call() ?? false) {
        didCancel = true;
        return _cancelledDownloadFailure(assetUri, version);
      }
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return Failure(
          domain.NetworkFailure.withContext(
            message: 'Silent update asset download failed',
            context: <String, dynamic>{
              'operation': 'silentUpdateDownload',
              'status_code': statusCode,
              'asset_url': assetUri.toString(),
            },
          ),
        );
      }

      var effectiveStartOffset = startOffset;
      final acceptedResume = statusCode == 206;
      if (startOffset > 0 && !acceptedResume) {
        effectiveStartOffset = 0;
        if (destination.existsSync()) {
          destination.deleteSync();
        }
      }

      final reported = response.headers.value(HttpHeaders.contentLengthHeader);
      final reportedLength = reported == null ? -1 : int.tryParse(reported) ?? -1;
      if (reportedLength > 0 && effectiveStartOffset + reportedLength > expectedSize) {
        return Failure(
          domain.ValidationFailure.withContext(
            message: 'Silent update asset download exceeded appcast length',
            context: <String, dynamic>{
              'operation': 'silentUpdateDownload',
              'version': version,
              'expected_size': expectedSize,
              'content_length': reportedLength,
              'start_offset': effectiveStartOffset,
              'asset_url': assetUri.toString(),
            },
          ),
        );
      }

      final body = response.data;
      if (body == null) {
        return Failure(
          domain.NetworkFailure.withContext(
            message: 'Silent update asset download failed',
            context: <String, dynamic>{
              'operation': 'silentUpdateDownload',
              'asset_url': assetUri.toString(),
            },
          ),
        );
      }

      final sink = effectiveStartOffset > 0 ? destination.openWrite(mode: FileMode.append) : destination.openWrite();
      try {
        var downloadedBytes = effectiveStartOffset;
        await for (final chunk in body.stream) {
          armStallTimer();
          if (cancelRequested?.call() ?? false) {
            didCancel = true;
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
    } on DioException catch (error) {
      if (didTimeOut) {
        return _downloadTimeoutFailure(assetUri, error);
      }
      if (didCancel || (cancelRequested?.call() ?? false)) {
        return _cancelledDownloadFailure(assetUri, version);
      }
      if (error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.connectionTimeout) {
        return _downloadTimeoutFailure(assetUri, error);
      }
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        return Failure(
          domain.NetworkFailure.withContext(
            message: 'Silent update asset download failed',
            context: <String, dynamic>{
              'operation': 'silentUpdateDownload',
              'status_code': statusCode,
              'asset_url': assetUri.toString(),
            },
          ),
        );
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
    } on TimeoutException catch (error) {
      return _downloadTimeoutFailure(assetUri, error);
    } on Exception catch (error) {
      if (didTimeOut) {
        return _downloadTimeoutFailure(assetUri, error);
      }
      if (didCancel) {
        return _cancelledDownloadFailure(assetUri, version);
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
      stallTimer?.cancel();
      cancelPollTimer?.cancel();
    }
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
}
