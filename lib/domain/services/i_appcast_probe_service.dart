import 'package:result_dart/result_dart.dart';

class AppcastProbeResult {
  const AppcastProbeResult({
    required this.requestUrl,
    this.latestVersion,
    this.assetUrl,
    this.assetSize,
    this.assetName,
    this.sha256,
    this.os,
    this.channel,
    this.rolloutPercentage,
    this.itemCount,
    this.edSignature,
    this.manifestUrl,
    this.manifestSha256,
    this.manifestSignature,
    this.releaseNotes,
    this.releaseNotesUrl,
  });

  final String requestUrl;
  final String? latestVersion;
  final String? assetUrl;
  final int? assetSize;
  final String? assetName;
  final String? sha256;
  final String? os;
  final String? channel;
  final int? rolloutPercentage;
  final int? itemCount;

  /// Base64-encoded Ed25519 signature taken from the `plug:edSignature`
  /// attribute of the enclosure. `null` when the publisher has not signed
  /// this item yet. Verification happens in the coordinator using the
  /// configured public key, so this field is just the raw transport value.
  final String? edSignature;

  /// New releases bind these fields to the enclosure with a separate signature.
  /// Legacy enclosures without a manifest remain readable during transition.
  final String? manifestUrl;
  final String? manifestSha256;
  final String? manifestSignature;

  /// Release notes text, taken from the `<description>` element of the item.
  /// Already trimmed; rendering is the UI's responsibility (basic markdown
  /// allowed). `null` when the publisher omitted the description.
  final String? releaseNotes;

  /// External URL to a release notes page (from `<sparkle:releaseNotesLink>`).
  /// Complements [releaseNotes] when the description is too short to be
  /// useful by itself.
  final String? releaseNotesUrl;
}

abstract interface class IAppcastProbeService {
  Future<Result<AppcastProbeResult>> probeLatest({
    required String feedUrl,
    bool Function()? cancelRequested,
    Duration timeout = const Duration(seconds: 10),
  });
}
