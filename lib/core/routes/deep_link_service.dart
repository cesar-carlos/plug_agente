import 'package:flutter/foundation.dart';

/// Service for handling deep links on desktop platforms.
///
/// Supports protocol handlers like `plugdb://config/abc123` on Windows.
class DeepLinkService {
  DeepLinkService();

  /// Extracts the initial deep link from command-line arguments.
  ///
  /// On Windows, deep links are passed as arguments when the app is
  /// launched from a protocol handler (e.g., `plugdb://config/123`).
  String? getInitialLink(List<String> args) {
    for (final arg in args) {
      if (arg.startsWith('plugdb://') || arg.startsWith('http://') || arg.startsWith('https://')) {
        return arg;
      }
    }
    return null;
  }

  /// Converts a deep link URL to an internal route path.
  ///
  /// Examples:
  /// - `plugdb://config` -> `/config`
  /// - `plugdb://config/abc123` -> `/config/abc123`
  /// - `plugdb://playground?id=xyz` -> `/playground?id=xyz`
  String? deepLinkToRoute(String deepLink) {
    try {
      // Handle custom protocol (plugdb://)
      if (deepLink.startsWith('plugdb://')) {
        // Manual parsing since Uri.parse doesn't handle unknown schemes well
        final withoutScheme = deepLink.replaceFirst('plugdb://', '');
        final queryIndex = withoutScheme.indexOf('?');

        String path;
        String? queryString;

        if (queryIndex >= 0) {
          path = withoutScheme.substring(0, queryIndex);
          queryString = withoutScheme.substring(queryIndex + 1);
        } else {
          path = withoutScheme;
        }

        // Build route
        final routePath = path.isEmpty ? '/' : '/$path';
        if (queryString != null && queryString.isNotEmpty) {
          return '$routePath?$queryString';
        }
        return routePath;
      }

      // Handle http/https (for web or future use)
      final uri = Uri.parse(deepLink);
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return uri.path;
      }

      return null;
    } on Exception catch (e) {
      if (kDebugMode) {
        print('Error parsing deep link: $e');
      }
      return null;
    }
  }

  /// Returns example deep links for documentation/testing.
  static const Map<String, String> examples = {
    'Open Dashboard': 'plugdb:///',
    'Open Config': 'plugdb://config',
    'Edit Config by ID': 'plugdb://config/abc-123-def',
    'Open Config with WebSocket tab': 'plugdb://config?tab=websocket',
    'Open Playground': 'plugdb://playground',
    'Open Playground with config': 'plugdb://playground?id=config-123',
  };

  /// Creates a deep link URL for a given route and parameters.
  ///
  /// Example:
  /// ```dart
  /// DeepLinkService().createDeepLink('/config', {'id': 'abc123'});
  /// // Returns: 'plugdb://config/abc123'
  /// ```
  String createDeepLink(
    String route, {
    Map<String, String>? queryParameters,
  }) {
    // Build query string manually
    final queryString = queryParameters != null && queryParameters.isNotEmpty
        ? '?${queryParameters.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';

    // Build path (remove leading slash for plugdb:// format)
    final path = route.startsWith('/') ? route.substring(1) : route;
    return 'plugdb://$path$queryString';
  }

  /// Validates if a deep link URL is properly formatted.
  bool isValidDeepLink(String? link) {
    if (link == null || link.isEmpty) return false;

    // Check for valid schemes
    if (link.startsWith('plugdb://') || link.startsWith('http://') || link.startsWith('https://')) {
      // Basic format validation: must have something after ://
      final parts = link.split('://');
      if (parts.length < 2) return false;
      return parts[1].isNotEmpty;
    }

    return false;
  }
}
