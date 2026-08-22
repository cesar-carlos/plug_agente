/// Shared installer → app handshake for per-user auto-start.
///
/// Must match [constants/autostart_request_marker.txt] and
/// [installer/constants.iss] (`AutostartRequestMarker`).
class AutostartInstallRequestConstants {
  AutostartInstallRequestConstants._();

  static const String markerFileName = 'autostart-requested';
}
