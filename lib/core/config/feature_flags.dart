import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

/// Feature flags for controlling rollout and experimentation.
class FeatureFlags {
  FeatureFlags(this._prefs);

  final IAppSettingsStore _prefs;

  // Keys
  static const _keyEnableBinaryPayload = 'feature_enable_binary_payload';
  static const _keyEnableCompression = 'feature_enable_compression';
  static const _keyOutboundCompressionMode = 'feature_outbound_compression_mode';
  static const _keyCompressionThreshold = 'feature_compression_threshold';
  static const _keyEnableClientTokenAuthorization = 'feature_enable_client_token_authorization';
  static const _keyEnableSocketApiVersionMeta = 'feature_enable_socket_api_version_meta';
  static const _keyEnableSocketNotificationsContract = 'feature_enable_socket_notifications_contract';
  static const _keyEnableSocketBatchStrictValidation = 'feature_enable_socket_batch_strict_validation';
  static const _keyEnableSocketIdempotency = 'feature_enable_socket_idempotency';
  static const _keyEnableSocketTimeoutByStage = 'feature_enable_socket_timeout_by_stage';
  static const _keyEnableSocketDeliveryGuarantees = 'feature_enable_socket_delivery_guarantees';
  static const _keyEnableSocketCancelMethod = 'feature_enable_socket_cancel_method';
  static const _keyEnableSocketSchemaValidation = 'feature_enable_socket_schema_validation';
  static const _keyEnableSocketOutgoingContractValidation = 'feature_enable_socket_outgoing_contract_validation';
  static const _keyEnableSocketSummarizeLargePayloadLogs = 'feature_enable_socket_summarize_large_payload_logs';
  static const _keyEnableSocketJwksValidation = 'feature_enable_socket_jwks_validation';
  static const _keyEnableSocketRevokedTokenInSession = 'feature_enable_socket_revoked_token_in_session';
  static const _keyEnableSocketStreamingChunks = 'feature_enable_socket_streaming_chunks';
  static const _keyEnableSocketBackpressure = 'feature_enable_socket_backpressure';
  static const _keyEnableSocketStreamingFromDb = 'feature_enable_socket_streaming_from_db';
  static const _keyEnableTokenAudit = 'feature_enable_token_audit';
  static const _keyEnablePayloadSigning = 'feature_enable_payload_signing';
  static const _keyEnableOdbcPaginatedSqlDebugLog = 'feature_enable_odbc_paginated_sql_debug_log';

  /// Whether binary payload is enabled.
  bool get enableBinaryPayload => _prefs.getBool(_keyEnableBinaryPayload) ?? true;

  Future<void> setEnableBinaryPayload(bool value) async {
    await _prefs.setBool(_keyEnableBinaryPayload, value);
  }

  /// Whether outbound compression is enabled (any mode other than `none`).
  bool get enableCompression => outboundCompressionMode != OutboundCompressionMode.none;

  /// Persisted strategy for agent -> hub PayloadFrame compression.
  OutboundCompressionMode get outboundCompressionMode {
    final stored = _prefs.getString(_keyOutboundCompressionMode);
    if (stored == OutboundCompressionMode.none.storageName) {
      return OutboundCompressionMode.none;
    }
    if (stored == OutboundCompressionMode.gzip.storageName) {
      return OutboundCompressionMode.gzip;
    }
    if (stored == OutboundCompressionMode.auto.storageName) {
      return OutboundCompressionMode.auto;
    }
    return (_prefs.getBool(_keyEnableCompression) ?? true)
        ? OutboundCompressionMode.gzip
        : OutboundCompressionMode.none;
  }

  Future<void> setOutboundCompressionMode(OutboundCompressionMode mode) async {
    await _prefs.setString(_keyOutboundCompressionMode, mode.storageName);
    await _prefs.setBool(
      _keyEnableCompression,
      mode != OutboundCompressionMode.none,
    );
  }

  Future<void> setEnableCompression(bool value) async {
    if (value) {
      await _prefs.setBool(_keyEnableCompression, true);
      final stored = _prefs.getString(_keyOutboundCompressionMode);
      if (stored == null || stored == OutboundCompressionMode.none.storageName) {
        await _prefs.setString(
          _keyOutboundCompressionMode,
          OutboundCompressionMode.gzip.storageName,
        );
      }
    } else {
      await setOutboundCompressionMode(OutboundCompressionMode.none);
    }
  }

  /// Compression threshold in bytes.
  int get compressionThreshold => _prefs.getInt(_keyCompressionThreshold) ?? 1024;

  Future<void> setCompressionThreshold(int value) async {
    await _prefs.setInt(_keyCompressionThreshold, value);
  }

  /// Whether client token authorization is enabled (enforcement before SQL).
  bool get enableClientTokenAuthorization => _prefs.getBool(_keyEnableClientTokenAuthorization) ?? true;

  Future<void> setEnableClientTokenAuthorization(bool value) async {
    await _prefs.setBool(_keyEnableClientTokenAuthorization, value);
  }

  /// Whether to include api_version and meta in RPC v2 requests/responses.
  bool get enableSocketApiVersionMeta => _prefs.getBool(_keyEnableSocketApiVersionMeta) ?? true;

  Future<void> setEnableSocketApiVersionMeta(bool value) async {
    await _prefs.setBool(_keyEnableSocketApiVersionMeta, value);
  }

  /// Whether to enforce notification contract (request without id, no response).
  bool get enableSocketNotificationsContract => _prefs.getBool(_keyEnableSocketNotificationsContract) ?? true;

  Future<void> setEnableSocketNotificationsContract(bool value) async {
    await _prefs.setBool(_keyEnableSocketNotificationsContract, value);
  }

  /// Whether to enforce strict batch validation (unique IDs, limits).
  bool get enableSocketBatchStrictValidation => _prefs.getBool(_keyEnableSocketBatchStrictValidation) ?? true;

  Future<void> setEnableSocketBatchStrictValidation(bool value) async {
    await _prefs.setBool(_keyEnableSocketBatchStrictValidation, value);
  }

  /// Whether to deduplicate requests by idempotency_key.
  bool get enableSocketIdempotency => _prefs.getBool(_keyEnableSocketIdempotency) ?? false;

  Future<void> setEnableSocketIdempotency(bool value) async {
    await _prefs.setBool(_keyEnableSocketIdempotency, value);
  }

  /// Whether to classify timeouts by stage (SQL, transport, ack).
  bool get enableSocketTimeoutByStage => _prefs.getBool(_keyEnableSocketTimeoutByStage) ?? false;

  Future<void> setEnableSocketTimeoutByStage(bool value) async {
    await _prefs.setBool(_keyEnableSocketTimeoutByStage, value);
  }

  /// Whether to enforce delivery guarantees (ack/retry) for critical events.
  bool get enableSocketDeliveryGuarantees => _prefs.getBool(_keyEnableSocketDeliveryGuarantees) ?? false;

  Future<void> setEnableSocketDeliveryGuarantees(bool value) async {
    await _prefs.setBool(_keyEnableSocketDeliveryGuarantees, value);
  }

  /// Whether sql.cancel method is enabled for cancelling in-flight queries.
  bool get enableSocketCancelMethod => _prefs.getBool(_keyEnableSocketCancelMethod) ?? true;

  Future<void> setEnableSocketCancelMethod(bool value) async {
    await _prefs.setBool(_keyEnableSocketCancelMethod, value);
  }

  /// Whether to validate RPC request payload against JSON schema at entry.
  bool get enableSocketSchemaValidation => _prefs.getBool(_keyEnableSocketSchemaValidation) ?? true;

  Future<void> setEnableSocketSchemaValidation(bool value) async {
    await _prefs.setBool(_keyEnableSocketSchemaValidation, value);
  }

  /// Validates outgoing `rpc:response` bodies against the RPC contract schema.
  ///
  /// Incoming request validation is still controlled by
  /// `enableSocketSchemaValidation`. When both are enabled, very large outgoing
  /// payloads may skip validation (see
  /// `ConnectionConstants.socketOutgoingContractValidationMaxBytes`).
  bool get enableSocketOutgoingContractValidation => _prefs.getBool(_keyEnableSocketOutgoingContractValidation) ?? true;

  Future<void> setEnableSocketOutgoingContractValidation(bool value) async {
    await _prefs.setBool(_keyEnableSocketOutgoingContractValidation, value);
  }

  /// When true, large payloads passed to the socket message tracer are replaced
  /// by a compact summary to avoid copying huge maps/lists through the callback.
  bool get enableSocketSummarizeLargePayloadLogs => _prefs.getBool(_keyEnableSocketSummarizeLargePayloadLogs) ?? true;

  Future<void> setEnableSocketSummarizeLargePayloadLogs(bool value) async {
    await _prefs.setBool(_keyEnableSocketSummarizeLargePayloadLogs, value);
  }

  /// Whether to cryptographically validate client tokens via JWKS
  /// (issuer, audience, kid, algorithm allowlist).
  bool get enableSocketJwksValidation => _prefs.getBool(_keyEnableSocketJwksValidation) ?? false;

  Future<void> setEnableSocketJwksValidation(bool value) async {
    await _prefs.setBool(_keyEnableSocketJwksValidation, value);
  }

  /// Whether to reject tokens in revoked store for session (no reconnect needed).
  bool get enableSocketRevokedTokenInSession => _prefs.getBool(_keyEnableSocketRevokedTokenInSession) ?? false;

  Future<void> setEnableSocketRevokedTokenInSession(bool value) async {
    await _prefs.setBool(_keyEnableSocketRevokedTokenInSession, value);
  }

  /// Whether to send large query results as ordered chunks (rpc:chunk,
  /// rpc:complete) instead of a single payload.
  bool get enableSocketStreamingChunks => _prefs.getBool(_keyEnableSocketStreamingChunks) ?? false;

  Future<void> setEnableSocketStreamingChunks(bool value) async {
    await _prefs.setBool(_keyEnableSocketStreamingChunks, value);
  }

  /// Whether to apply backpressure via rpc:stream.pull (client controls
  /// consumption rate).
  bool get enableSocketBackpressure => _prefs.getBool(_keyEnableSocketBackpressure) ?? false;

  Future<void> setEnableSocketBackpressure(bool value) async {
    await _prefs.setBool(_keyEnableSocketBackpressure, value);
  }

  /// Whether to stream large results directly from DB (reduces memory).
  bool get enableSocketStreamingFromDb => _prefs.getBool(_keyEnableSocketStreamingFromDb) ?? false;

  Future<void> setEnableSocketStreamingFromDb(bool value) async {
    await _prefs.setBool(_keyEnableSocketStreamingFromDb, value);
  }

  /// Whether to persist token management audit trail (create/revoke/revoked).
  bool get enableTokenAudit => _prefs.getBool(_keyEnableTokenAudit) ?? false;

  Future<void> setEnableTokenAudit(bool value) async {
    await _prefs.setBool(_keyEnableTokenAudit, value);
  }

  /// Whether to sign outgoing payloads and verify incoming signatures (HMAC-SHA256).
  bool get enablePayloadSigning => _prefs.getBool(_keyEnablePayloadSigning) ?? false;

  Future<void> setEnablePayloadSigning(bool value) async {
    await _prefs.setBool(_keyEnablePayloadSigning, value);
  }

  /// Logs final paginated SQL at debug level when the agent rewrites queries
  /// (managed pagination). Off by default; avoid enabling in production with
  /// sensitive data.
  bool get enableOdbcPaginatedSqlDebugLog => _prefs.getBool(_keyEnableOdbcPaginatedSqlDebugLog) ?? false;

  Future<void> setEnableOdbcPaginatedSqlDebugLog(bool value) async {
    await _prefs.setBool(_keyEnableOdbcPaginatedSqlDebugLog, value);
  }

  /// Resets all feature flags to default values.
  Future<void> resetToDefaults() async {
    await setEnableBinaryPayload(true);
    await setOutboundCompressionMode(OutboundCompressionMode.gzip);
    await setCompressionThreshold(1024);
    await setEnableClientTokenAuthorization(true);
    await setEnableSocketApiVersionMeta(true);
    await setEnableSocketNotificationsContract(true);
    await setEnableSocketBatchStrictValidation(true);
    await setEnableSocketIdempotency(false);
    await setEnableSocketTimeoutByStage(false);
    await setEnableSocketDeliveryGuarantees(false);
    await setEnableSocketCancelMethod(true);
    await setEnableSocketSchemaValidation(true);
    await setEnableSocketOutgoingContractValidation(true);
    await setEnableSocketSummarizeLargePayloadLogs(true);
    await setEnableSocketJwksValidation(false);
    await setEnableSocketRevokedTokenInSession(false);
    await setEnableSocketStreamingChunks(false);
    await setEnableSocketBackpressure(false);
    await setEnableSocketStreamingFromDb(false);
    await setEnableTokenAudit(false);
    await setEnablePayloadSigning(false);
    await setEnableOdbcPaginatedSqlDebugLog(false);
  }
}
