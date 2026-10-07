import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/domain/errors/failures.dart' show ConfigurationFailure;
import 'package:plug_agente/domain/services/i_privileged_updater.dart';
import 'package:result_dart/result_dart.dart';

typedef UpdaterRequestTransport = Future<Result<Map<String, dynamic>>> Function(Map<String, Object?> request);

/// The signed, protected native client authenticates the caller to the service.
/// Only this fixed executable is used; no shell or arbitrary command is accepted.
class WindowsPrivilegedUpdater implements IPrivilegedUpdater {
  WindowsPrivilegedUpdater({String? programFiles, UpdaterRequestTransport? requestTransport})
    : _requestTransport = requestTransport,
      _client = p.join(
        programFiles ?? Platform.environment['ProgramFiles'] ?? r'C:\Program Files',
        'PlugAgenteUpdater',
        'plug_update_client.exe',
      );

  final String _client;
  final UpdaterRequestTransport? _requestTransport;
  static const int _maxBytes = 1024 * 1024;

  Future<Result<Map<String, dynamic>>> _call(Map<String, Object?> request) =>
      _requestTransport?.call(request) ?? _callNative(request);

  Future<Result<Map<String, dynamic>>> _callNative(Map<String, Object?> request) async {
    Process? process;
    try {
      final encoded = utf8.encode(jsonEncode({'protocol': 1, ...request}));
      if (encoded.length > _maxBytes) throw const FormatException('IPC message too large');
      process = await Process.start(_client, const ['--ipc']);
      final outputs = Future.wait([_readBounded(process.stdout), _readBounded(process.stderr)]);
      process.stdin.add(encoded);
      await process.stdin.close();
      final responseBytes = (await outputs.timeout(const Duration(seconds: 30))).first;
      final exit = await process.exitCode.timeout(const Duration(seconds: 5));
      final response = jsonDecode(utf8.decode(responseBytes)) as Map<String, dynamic>;
      if (exit != 0 || response['ok'] != true) {
        final rawReason = response['code'];
        final reason = rawReason is String && RegExp(r'^[a-z][a-z_]{0,63}$').hasMatch(rawReason)
            ? rawReason
            : 'updater_rejected';
        return Failure(
          ConfigurationFailure.withContext(
            message: response['code'] == 'authorization_required'
                ? 'A atualização exige autorização administrativa adicional.'
                : 'A atualização automática está indisponível ou adiada.',
            context: {
              'reason': reason,
              if (response['missingCapabilities'] is List) 'missing_capabilities': response['missingCapabilities'],
            },
          ),
        );
      }
      return Success(response);
    } on Object catch (error) {
      return Failure(
        ConfigurationFailure.withContext(
          message: 'Não foi possível consultar o serviço de atualização.',
          cause: error,
          context: const {'reason': 'updater_unavailable'},
        ),
      );
    } finally {
      // This kills only our unprivileged IPC proxy, never the service or installer.
      process?.kill();
    }
  }

  Future<List<int>> _readBounded(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > _maxBytes) throw const FormatException('IPC response too large');
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<Result<UpdaterStatus>> _statusCall(Map<String, Object?> request) async {
    final response = await _call(request);
    if (response.isError()) return Failure(response.exceptionOrNull()!);
    try {
      return Success(_parseStatus(response.getOrThrow()));
    } on Object catch (error) {
      return Failure(_invalidResponse(error));
    }
  }

  UpdaterStatus _parseStatus(Map<String, dynamic> response) {
    final value = response['status'] as Map<String, dynamic>;
    if (value['protocol'] is! int || value['protocol'] != 1) {
      throw const FormatException('Unsupported IPC protocol');
    }
    final operation = value['operationId'] as String?;
    if (operation != null && !RegExp(r'^[0-9a-f]{32}$').hasMatch(operation)) {
      throw const FormatException('Invalid operation identity');
    }
    for (final key in const ['rebootPending', 'ownedByCaller', 'restartOnly', 'finalizationPending']) {
      if (value[key] != null && value[key] is! bool) throw FormatException('Invalid $key');
    }
    if (value['retryAfterUnixMillis'] != null && value['retryAfterUnixMillis'] is! int) {
      throw const FormatException('Invalid recovery retry date');
    }
    return UpdaterStatus(
      phase: UpdaterPhase.values.byName(value['state'] as String),
      operationId: operation,
      version: value['version'] as String?,
      reason: value['reason'] as String?,
      missingCapabilities: List<String>.from(value['missingCapabilities'] as List? ?? const []),
      rebootPending: value['rebootPending'] == true,
      ownedByCaller: value['ownedByCaller'] == true,
      restartOnly: value['restartOnly'] == true,
      finalizationPending: value['finalizationPending'] == true,
      retryAfter: value['retryAfterUnixMillis'] is int
          ? DateTime.fromMillisecondsSinceEpoch(value['retryAfterUnixMillis'] as int, isUtc: true)
          : null,
    );
  }

  ConfigurationFailure _invalidResponse(Object error) => ConfigurationFailure.withContext(
    message: 'Resposta inválida do serviço de atualização.',
    cause: error,
    context: const {'reason': 'invalid_updater_response'},
  );

  @override
  Future<Result<UpdaterCapabilities>> capabilities() async {
    final response = await _call({'command': 'capabilities'});
    if (response.isError()) return Failure(response.exceptionOrNull()!);
    try {
      final value = response.getOrThrow()['capabilities'] as Map<String, dynamic>;
      if (value['protocol'] is! int ||
          value['protocol'] != 1 ||
          !{'stable', 'beta', 'internal'}.contains(value['channel'])) {
        throw const FormatException('Unsupported capabilities');
      }
      return Success(
        UpdaterCapabilities(
          authorized: value['authorized'] as bool,
          applicationReady: value['applicationReady'] as bool,
          channel: value['channel'] as String,
          approved: List<String>.unmodifiable(List<String>.from(value['approved'] as List)),
          recoveryContract: value['recoveryContract'] as int? ?? 0,
        ),
      );
    } on Object catch (error) {
      return Failure(_invalidResponse(error));
    }
  }

  @override
  Future<Result<UpdaterStatus>> status() => _statusCall({'command': 'status'});
  @override
  Future<Result<UpdaterStatus>> prepare({required Map<String, Object?> manifest, required String installerPath}) =>
      _statusCall({'command': 'prepare', 'manifest': manifest, 'installerPath': installerPath});
  @override
  Future<Result<UpdaterStatus>> cancel(String operationId) =>
      _statusCall({'command': 'cancel', 'operationId': operationId});
  @override
  Future<Result<UpdaterStatus>> requestApplicationRecovery({required String operationId, required int appPid}) =>
      _statusCall({'command': 'recoverApplication', 'operationId': operationId, 'appPid': appPid});
  @override
  Future<Result<UpdaterStartConfirmation>> start({
    required String operationId,
    required int appPid,
    required String dataDirectory,
    required String encryptedSecretsSnapshot,
  }) async {
    final response = await _call({
      'command': 'start',
      'operationId': operationId,
      'appPid': appPid,
      'dataDirectory': dataDirectory,
      'secretsSnapshot': encryptedSecretsSnapshot,
    });
    if (response.isError()) return Failure(response.exceptionOrNull()!);
    try {
      final value = response.getOrThrow();
      final status = _parseStatus(value);
      final nonce = value['healthNonce'] as String;
      if (status.operationId != operationId || !RegExp(r'^[0-9a-f]{32}$').hasMatch(nonce)) {
        throw const FormatException('Invalid dispatch confirmation');
      }
      return Success(UpdaterStartConfirmation(status: status, healthNonce: nonce));
    } on Object catch (error) {
      return Failure(_invalidResponse(error));
    }
  }

  @override
  Future<Result<void>> confirmHealth({
    required String operationId,
    required String version,
    required String nonce,
  }) async {
    final result = await _call({
      'command': 'health',
      'operationId': operationId,
      'version': version,
      'nonce': nonce,
      'appPid': pid,
    });
    return result.fold((_) => const Success(unit), Failure.new);
  }

  Future<Result<Map<String, dynamic>>> validationContext(String operationId, String nonce) =>
      _call({'command': 'validationContext', 'operationId': operationId, 'nonce': nonce, 'appPid': pid});

  Future<Result<void>> confirmRestoration(String operationId, String nonce) async {
    final result = await _call({'command': 'restored', 'operationId': operationId, 'nonce': nonce, 'appPid': pid});
    return result.fold((_) => const Success(unit), Failure.new);
  }
}
