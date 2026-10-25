import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/errors/silent_install_failure.dart';
import 'package:plug_agente/domain/services/appcast_release_selector.dart';
import 'package:plug_agente/domain/services/i_appcast_probe_service.dart';
import 'package:result_dart/result_dart.dart';
import 'package:xml/xml.dart';

class AppcastProbeService implements IAppcastProbeService {
  AppcastProbeService({Dio? dio, String Function()? channelResolver})
    : _dio = dio ?? _createProbeDio(),
      _channelResolver = channelResolver ?? (() => resolveAutoUpdateChannel(environment: AppEnvironment.snapshot()));

  final Dio _dio;
  final String Function() _channelResolver;

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
  Future<Result<AppcastProbeResult>> probeLatest({
    required String feedUrl,
    bool Function()? cancelRequested,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final cancellation = CancelToken();
    final monitor = cancelRequested == null
        ? null
        : Timer.periodic(const Duration(milliseconds: 100), (_) {
            if (cancelRequested()) cancellation.cancel();
          });
    try {
      if (cancelRequested?.call() ?? false) {
        return Failure(SilentInstallCancellationFailure(message: 'Atualização cancelada.'));
      }
      final bytes = await _download(feedUrl, cancellation).timeout(timeout);
      return Success(_parse(feedUrl, utf8.decode(bytes)));
    } on TimeoutException catch (error) {
      cancellation.cancel();
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'O tempo para consultar atualizações esgotou.',
          cause: error,
          context: const {'reason': 'appcast_timeout'},
        ),
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        return Failure(SilentInstallCancellationFailure(message: 'Atualização cancelada.'));
      }
      return Failure(
        domain.NetworkFailure.withContext(
          message: 'Não foi possível consultar atualizações.',
          cause: error,
          context: {'reason': 'appcast_network_failed', 'status': error.response?.statusCode},
        ),
      );
    } on FormatException catch (error) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'O catálogo de atualizações é inválido.',
          cause: error,
          context: const {'reason': 'appcast_invalid'},
        ),
      );
    } on XmlException catch (error) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'O catálogo de atualizações é inválido.',
          cause: error,
          context: const {'reason': 'appcast_invalid_xml'},
        ),
      );
    } on Object catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Não foi possível preparar a consulta de atualizações.',
          cause: error,
          context: const {'reason': 'appcast_unavailable'},
        ),
      );
    } finally {
      monitor?.cancel();
      cancellation.cancel();
    }
  }

  Future<List<int>> _download(String feedUrl, CancelToken cancellation) async {
    var uri = Uri.parse(feedUrl);
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!isSparkleFeedUrl(uri.toString())) throw const FormatException('Appcast URL rejected');
      final response = await _dio.getUri<ResponseBody>(
        uri,
        cancelToken: cancellation,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
          headers: {'User-Agent': _userAgent, 'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
        ),
      );
      final body = response.data;
      if (body == null) throw const FormatException('Missing appcast');
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        await body.stream.listen(null).cancel();
        final location = response.headers.value('location');
        if (location == null || redirects == 5) throw const FormatException('Invalid redirect');
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await body.stream.listen(null).cancel();
        throw const FormatException('Unexpected appcast response');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        if (bytes.length + chunk.length > _maxAppcastBytes) throw const FormatException('Appcast too large');
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }
    throw const FormatException('Too many redirects');
  }

  AppcastProbeResult _parse(String feedUrl, String body) {
    final document = XmlDocument.parse(body);
    final channel = _firstChildElementByName(document.rootElement, 'channel');
    if (channel == null) {
      throw const FormatException('Appcast missing channel element');
    }

    final items = channel.childElements.where((element) => _matchesLocalName(element, 'item')).toList();
    if (items.isEmpty) {
      throw const FormatException('Appcast missing item element');
    }

    final releases = <AppcastProbeResult>[];
    String? firstCandidateError;
    final configuredChannel = _channelResolver();
    for (final item in items) {
      final enclosure = _firstChildElementByName(item, 'enclosure');
      if (enclosure == null) {
        firstCandidateError ??= 'Latest appcast item is missing enclosure';
        continue;
      }
      // Releases before channels were introduced belong to stable only.
      if ((_plugChannelFromEnclosure(enclosure) ?? defaultAutoUpdateChannel) != configuredChannel) continue;

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
      releases.add(_resultFromCandidate(feedUrl: feedUrl, itemCount: items.length, candidate: candidate));
    }
    final selected = selectAppcastRelease(releases, channel: configuredChannel);
    if (selected != null) return selected;

    if (firstCandidateError != null) {
      throw FormatException(firstCandidateError);
    }

    throw const FormatException('Appcast missing supported Windows item');
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
      manifestUrl: _plugAttribute(enclosure, 'manifestUrl'),
      manifestSha256: _plugAttribute(enclosure, 'manifestSha256'),
      manifestSignature: _plugAttribute(enclosure, 'manifestSignature'),
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

  static String? _plugAttribute(XmlElement enclosure, String localName) => _namespacedAttributeValue(
    enclosure,
    localName: localName,
    prefix: 'plug',
    namespaceUri: _plugNamespace,
    qualifiedName: 'plug:$localName',
  );

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
