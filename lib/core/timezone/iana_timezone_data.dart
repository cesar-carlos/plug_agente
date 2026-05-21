import 'package:timezone/data/latest.dart' as tz_data;

bool _ianaTimeZoneDataLoaded = false;

/// Loads embedded IANA tzdb (from `package:timezone/data/latest.dart`).
///
/// Safe to call multiple times. Required before resolving IANA locations in
/// validators or schedulers.
void ensureIanaTimeZoneDataLoaded() {
  if (_ianaTimeZoneDataLoaded) {
    return;
  }
  tz_data.initializeTimeZones();
  _ianaTimeZoneDataLoaded = true;
}
