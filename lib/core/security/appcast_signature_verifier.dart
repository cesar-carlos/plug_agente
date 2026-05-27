import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Outcome of an [IAppcastSignatureVerifier.verifyEnclosure] call.
enum AppcastSignatureVerificationStatus {
  /// No `plug:edSignature` attribute was provided on the enclosure.
  /// Treat as `unsigned`: callers that require signing should reject this.
  missing,

  /// `plug:edSignature` is present but the public key is not configured
  /// (e.g., no `AUTO_UPDATE_FEED_PUBLIC_KEY` in the environment). The probe
  /// cannot decide; callers that require signing should reject this.
  publicKeyUnavailable,

  /// `plug:edSignature` is malformed (not base64) or the public key is not a
  /// valid 32-byte Ed25519 key.
  malformed,

  /// Signature was successfully verified against the canonical enclosure
  /// payload and the configured public key.
  valid,

  /// Signature did not verify (cryptographic mismatch). Likely a tampered
  /// feed item or a key rotation that the client has not picked up yet.
  invalid,
}

/// Verifies the optional `plug:edSignature` attribute on appcast enclosures.
///
/// The signature is Ed25519 over the canonical UTF-8 representation of the
/// enclosure's content fields (see [buildAppcastEnclosureSignable]). It binds
/// the publication to all fields that drive the silent update decision
/// (version, channel, rollout, asset URL/size, SHA-256, OS) so a passive
/// observer cannot swap, downgrade, or re-target a release without invalidating
/// the signature.
///
/// Verification is opt-in: clients require it only when the operator sets
/// `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true`. When the requirement is off,
/// the probe still records the [AppcastSignatureVerificationStatus] in
/// diagnostics so operators can observe signing rollout without blocking
/// the release pipeline.
///
/// The `base64PublicKey` argument accepts either a single base64 key or a
/// comma-separated list. Multi-key support enables rotation without an
/// installed-base outage:
/// during a rotation window the build embeds both the current and next key,
/// releases are signed by the current key, and once telemetry confirms the
/// older key is no longer in use the older key can be dropped from new builds.
abstract interface class IAppcastSignatureVerifier {
  Future<AppcastSignatureVerificationStatus> verifyEnclosure({
    required String canonicalPayload,
    required String? base64Signature,
    required String? base64PublicKey,
  });
}

class Ed25519AppcastSignatureVerifier implements IAppcastSignatureVerifier {
  Ed25519AppcastSignatureVerifier({Ed25519? algorithm}) : _algorithm = algorithm ?? Ed25519();

  final Ed25519 _algorithm;

  static const int _ed25519PublicKeyBytes = 32;
  static const int _ed25519SignatureBytes = 64;

  @override
  Future<AppcastSignatureVerificationStatus> verifyEnclosure({
    required String canonicalPayload,
    required String? base64Signature,
    required String? base64PublicKey,
  }) async {
    final signatureRaw = base64Signature?.trim();
    if (signatureRaw == null || signatureRaw.isEmpty) {
      return AppcastSignatureVerificationStatus.missing;
    }

    final keyCandidates = parseAppcastPublicKeys(base64PublicKey);
    if (keyCandidates.isEmpty) {
      return AppcastSignatureVerificationStatus.publicKeyUnavailable;
    }

    final Uint8List signatureBytes;
    try {
      signatureBytes = base64Decode(signatureRaw);
    } on FormatException {
      return AppcastSignatureVerificationStatus.malformed;
    }
    if (signatureBytes.length != _ed25519SignatureBytes) {
      return AppcastSignatureVerificationStatus.malformed;
    }

    final messageBytes = Uint8List.fromList(utf8.encode(canonicalPayload));

    // Track whether at least one key was structurally valid. If every key was
    // malformed, we surface `malformed` rather than `invalid` — the operator
    // configured garbage, not an attacker tampering with the feed.
    var sawValidKeyShape = false;

    for (final keyRaw in keyCandidates) {
      final Uint8List publicKeyBytes;
      try {
        publicKeyBytes = base64Decode(keyRaw);
      } on FormatException {
        continue;
      }
      if (publicKeyBytes.length != _ed25519PublicKeyBytes) {
        continue;
      }
      sawValidKeyShape = true;

      try {
        final publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
        final signature = Signature(signatureBytes, publicKey: publicKey);
        final ok = await _algorithm.verify(messageBytes, signature: signature);
        if (ok) {
          return AppcastSignatureVerificationStatus.valid;
        }
      } on Object {
        // Defensive: an unexpected library error for this key — try the next.
        continue;
      }
    }

    if (!sawValidKeyShape) {
      return AppcastSignatureVerificationStatus.malformed;
    }
    return AppcastSignatureVerificationStatus.invalid;
  }
}

/// Splits a comma-separated list of base64 Ed25519 public keys into trimmed,
/// non-empty entries. Tolerates whitespace around commas. Returns an empty
/// list when [raw] is null/blank.
///
/// Public so the probe and DI can share the same parsing rule.
List<String> parseAppcastPublicKeys(String? raw) {
  if (raw == null) return const <String>[];
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const <String>[];
  return trimmed
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

/// Canonical UTF-8 representation of a Sparkle enclosure's signable fields.
///
/// Fields are written one per line as `key=value\n` in lexicographic order
/// (stable across producers). Missing fields are still serialised with an
/// empty value so producers and verifiers agree on the shape.
String buildAppcastEnclosureSignable({
  required String version,
  required String os,
  required String sha256,
  required String channel,
  required int rolloutPercentage,
  required String assetUrl,
  required int assetSize,
}) {
  final entries = <String, String>{
    'asset_size': assetSize.toString(),
    'asset_url': assetUrl,
    'channel': channel,
    'os': os,
    'rollout_percentage': rolloutPercentage.toString(),
    'sha256': sha256.toLowerCase(),
    'version': version,
  };
  final sortedKeys = entries.keys.toList()..sort();
  final buffer = StringBuffer();
  for (final key in sortedKeys) {
    buffer
      ..write(key)
      ..write('=')
      ..write(entries[key])
      ..write('\n');
  }
  return buffer.toString();
}
