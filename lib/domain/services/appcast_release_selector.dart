import 'package:plug_agente/core/versioning/app_version_comparator.dart';
import 'package:plug_agente/domain/services/i_appcast_probe_service.dart';

AppcastProbeResult? selectAppcastRelease(Iterable<AppcastProbeResult> releases, {required String channel}) {
  AppcastProbeResult? windows;
  AppcastProbeResult? legacy;
  for (final release in releases) {
    if ((release.channel ?? 'stable') != channel || release.latestVersion == null) continue;
    if (release.os == 'windows') {
      if (windows == null || AppVersionComparator.compare(release.latestVersion!, windows.latestVersion!) > 0) {
        windows = release;
      }
    } else if (release.os == null || release.os!.isEmpty) {
      if (legacy == null || AppVersionComparator.compare(release.latestVersion!, legacy.latestVersion!) > 0) {
        legacy = release;
      }
    }
  }
  return windows ?? legacy;
}
