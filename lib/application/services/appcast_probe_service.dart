import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/versioning/app_version_comparator.dart';
import 'package:xml/xml.dart';

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
    this.errorMessage,
    this.edSignature,
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
  final String? errorMessage;

  /// Base64-encoded Ed25519 signature taken from the `plug:edSignature`
  /// attribute of the enclosure. `null` when the publisher has not signed
  /// this item yet. Verification happens in the coordinator using the
  /// configured public key, so this field is just the raw transport value.
  final String? edSignature;

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
  Future<AppcastProbeResult> probeLatest({
    required String feedUrl,
    Duration timeout = const Duration(seconds: 10),
  });
}

class AppcastProbeService implements IAppcastProbeService {
  AppcastProbeService({Dio? dio}) : _dio = dio ?? _createProbeDio();

  final Dio _dio;

  static const int _maxAppcastBytes = 1024 * 1024;
  static const String _sparkleNamespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle';
  static const String _plugNamespace = 'https://plug.se7esistemas.com/appcast';

  static String get _userAgent => 'PlugAgente/${AppConstants.appVersion} (Windows; Sparkle/appcast-probe)';

  static Dio _createProbeDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        headers: <String, dynamic>{
          'Accept': 'application/rss+xml,text/xml,*/*',
        },
      ),
    );
    return dio;
  }

  @override
  Future<AppcastProbeResult> probeLatest({
    required String feedUrl,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.tryParse(feedUrl);
    if (uri == null || !isSparkleFeedUrl(feedUrl)) {
      return AppcastProbeResult(
        requestUrl: feedUrl,
        errorMessage: 'Feed URL is not an allowed Sparkle appcast URL',
      );
    }

    try {
      final response = await _dio.get<List<int>>(
        feedUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          headers: <String, String>{
            'User-Agent': _userAgent,
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          errorMessage: 'HTTP $statusCode',
        );
      }

      final bytes = response.data ?? const <int>[];
      if (bytes.length > _maxAppcastBytes) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          errorMessage: 'Appcast response exceeded $_maxAppcastBytes bytes',
        );
      }

      final body = utf8.decode(bytes, allowMalformed: true);
      final document = XmlDocument.parse(body);
      final channel = _firstChildElementByName(document.rootElement, 'channel');
      if (channel == null) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          errorMessage: 'Appcast missing channel element',
        );
      }

      final items = channel.childElements.where((element) => _matchesLocalName(element, 'item')).toList();
      if (items.isEmpty) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          itemCount: 0,
          errorMessage: 'Appcast missing item element',
        );
      }

      _ProbeCandidate? bestWindowsCandidate;
      _ProbeCandidate? bestLegacyCandidate;
      String? firstCandidateError;
      for (final item in items) {
        final enclosure = _firstChildElementByName(item, 'enclosure');
        if (enclosure == null) {
          firstCandidateError ??= 'Latest appcast item is missing enclosure';
          continue;
        }

        final latestVersion = _sparkleVersionFromEnclosure(enclosure);
        if (latestVersion == null || latestVersion.isEmpty) {
          firstCandidateError ??= 'Latest appcast item is missing sparkle:version';
          continue;
        }

        final os = _sparkleOsFromEnclosure(enclosure);
        final candidate = _ProbeCandidate(
          item: item,
          enclosure: enclosure,
          latestVersion: latestVersion,
          os: os,
        );
        if (os == 'windows') {
          if (bestWindowsCandidate == null ||
              AppVersionComparator.compare(latestVersion, bestWindowsCandidate.latestVersion) > 0) {
            bestWindowsCandidate = candidate;
          }
        } else if (os == null || os.isEmpty) {
          if (bestLegacyCandidate == null ||
              AppVersionComparator.compare(latestVersion, bestLegacyCandidate.latestVersion) > 0) {
            bestLegacyCandidate = candidate;
          }
        }
      }

      if (bestWindowsCandidate != null) {
        return _resultFromCandidate(
          feedUrl: feedUrl,
          itemCount: items.length,
          candidate: bestWindowsCandidate,
        );
      }

      if (bestLegacyCandidate != null) {
        return _resultFromCandidate(
          feedUrl: feedUrl,
          itemCount: items.length,
          candidate: bestLegacyCandidate,
        );
      }

      if (firstCandidateError != null) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          itemCount: items.length,
          errorMessage: firstCandidateError,
        );
      }

      return AppcastProbeResult(
        requestUrl: feedUrl,
        itemCount: items.length,
        errorMessage: 'Appcast missing supported Windows item',
      );
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        return AppcastProbeResult(
          requestUrl: feedUrl,
          errorMessage: 'HTTP $statusCode',
        );
      }
      return AppcastProbeResult(
        requestUrl: feedUrl,
        errorMessage: error.message ?? error.toString(),
      );
    } on Exception catch (e) {
      return AppcastProbeResult(
        requestUrl: feedUrl,
        errorMessage: e.toString(),
      );
    }
  }

  static XmlElement? _firstChildElementByName(XmlElement parent, String name) {
    for (final child in parent.childElements) {
      if (_matchesLocalName(child, name)) {
        return child;
      }
    }
    return null;
  }

  static bool _matchesLocalName(XmlElement element, String expected) {
    return element.name.local.toLowerCase() == expected.toLowerCase();
  }

  static AppcastProbeResult _resultFromCandidate({
    required String feedUrl,
    required int itemCount,
    required _ProbeCandidate candidate,
  }) {
    final enclosure = candidate.enclosure;
    final assetUrl = _attributeValue(enclosure, 'url');
    return AppcastProbeResult(
      requestUrl: feedUrl,
      latestVersion: candidate.latestVersion,
      assetUrl: assetUrl,
      assetSize: _assetSizeFromEnclosure(enclosure),
      assetName: _assetNameFromUrl(assetUrl),
      sha256: _plugSha256FromEnclosure(enclosure),
      os: candidate.os,
      channel: _plugChannelFromEnclosure(enclosure),
      rolloutPercentage: _plugRolloutPercentageFromEnclosure(enclosure),
      itemCount: itemCount,
      edSignature: _plugEdSignatureFromEnclosure(enclosure),
      releaseNotes: _releaseNotesFromItem(candidate.item),
      releaseNotesUrl: _releaseNotesLinkFromItem(candidate.item),
    );
  }

  static String? _releaseNotesFromItem(XmlElement item) {
    final description = _firstChildElementByName(item, 'description');
    if (description == null) return null;
    final value = description.innerText.trim();
    return value.isEmpty ? null : value;
  }

  static String? _releaseNotesLinkFromItem(XmlElement item) {
    for (final child in item.childElements) {
      if (child.name.local.toLowerCase() == 'releasenoteslink' &&
          (child.name.prefix?.toLowerCase() == 'sparkle' || child.name.namespaceUri == _sparkleNamespace)) {
        final value = child.innerText.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  static String? _plugEdSignatureFromEnclosure(XmlElement enclosure) {
    return _namespacedAttributeValue(
      enclosure,
      localName: 'edSignature',
      prefix: 'plug',
      namespaceUri: _plugNamespace,
      qualifiedName: 'plug:edSignature',
    );
  }

  static String? _sparkleVersionFromEnclosure(XmlElement enclosure) {
    return _namespacedAttributeValue(
      enclosure,
      localName: 'version',
      prefix: 'sparkle',
      namespaceUri: _sparkleNamespace,
      qualifiedName: 'sparkle:version',
    );
  }

  static String? _sparkleOsFromEnclosure(XmlElement enclosure) {
    return _namespacedAttributeValue(
      enclosure,
      localName: 'os',
      prefix: 'sparkle',
      namespaceUri: _sparkleNamespace,
      qualifiedName: 'sparkle:os',
    )?.toLowerCase();
  }

  static String? _plugSha256FromEnclosure(XmlElement enclosure) {
    return _namespacedAttributeValue(
      enclosure,
      localName: 'sha256',
      prefix: 'plug',
      namespaceUri: _plugNamespace,
      qualifiedName: 'plug:sha256',
    )?.toLowerCase();
  }

  static String? _plugChannelFromEnclosure(XmlElement enclosure) {
    return _namespacedAttributeValue(
      enclosure,
      localName: 'channel',
      prefix: 'plug',
      namespaceUri: _plugNamespace,
      qualifiedName: 'plug:channel',
    )?.toLowerCase();
  }

  static int? _plugRolloutPercentageFromEnclosure(XmlElement enclosure) {
    final raw = _namespacedAttributeValue(
      enclosure,
      localName: 'rolloutPercentage',
      prefix: 'plug',
      namespaceUri: _plugNamespace,
      qualifiedName: 'plug:rolloutPercentage',
    );
    if (raw == null) {
      return null;
    }
    return int.tryParse(raw);
  }

  static String? _namespacedAttributeValue(
    XmlElement enclosure, {
    required String localName,
    required String prefix,
    required String namespaceUri,
    required String qualifiedName,
  }) {
    final expectedLocalName = localName.toLowerCase();
    final expectedQualifiedName = qualifiedName.toLowerCase();
    for (final attribute in enclosure.attributes) {
      final attributeLocalName = attribute.name.local.toLowerCase();
      final attributePrefix = attribute.name.prefix?.toLowerCase();
      final attributeNamespaceUri = attribute.name.namespaceUri;
      final qualified = attribute.name.qualified.toLowerCase();
      final isTargetAttribute =
          attributeLocalName == expectedLocalName &&
          (attributeNamespaceUri == namespaceUri || attributePrefix == prefix || qualified == expectedQualifiedName);
      if (!isTargetAttribute) {
        continue;
      }
      final value = attribute.value.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static String? _attributeValue(XmlElement element, String name) {
    final value = element.getAttribute(name)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static int? _assetSizeFromEnclosure(XmlElement enclosure) {
    final raw = _attributeValue(enclosure, 'length');
    if (raw == null) {
      return null;
    }
    return int.tryParse(raw);
  }

  static String? _assetNameFromUrl(String? assetUrl) {
    if (assetUrl == null) {
      return null;
    }
    final uri = Uri.tryParse(assetUrl);
    if (uri == null || uri.pathSegments.isEmpty) {
      return null;
    }
    final name = uri.pathSegments.last.trim();
    return name.isEmpty ? null : name;
  }
}

class _ProbeCandidate {
  const _ProbeCandidate({
    required this.item,
    required this.enclosure,
    required this.latestVersion,
    required this.os,
  });

  final XmlElement item;
  final XmlElement enclosure;
  final String latestVersion;
  final String? os;
}
