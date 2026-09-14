/// Cities prayer times can be calculated for, until one-time device location
/// (`geolocator`, `docs/plan.md` section 6) lands. Coordinates are city
/// centres; a few hundred metres off changes a time by well under a minute.
///
/// Every city here keeps Uzbekistan time: UTC+5 all year, no daylight saving.
library;

import 'package:adhan_dart/adhan_dart.dart' show Coordinates;

enum PrayerCity {
  tashkent('tashkent', 41.2995, 69.2401),
  nurafshon('nurafshon', 41.0167, 69.3417),
  andijan('andijan', 40.7821, 72.3442),
  bukhara('bukhara', 39.7681, 64.4556),
  fergana('fergana', 40.3842, 71.7843),
  guliston('guliston', 40.4897, 68.7842),
  jizzakh('jizzakh', 40.1250, 67.8808),
  namangan('namangan', 40.9983, 71.6726),
  navoiy('navoiy', 40.1039, 65.3739),
  nukus('nukus', 42.4531, 59.6103),
  qarshi('qarshi', 38.8606, 65.7891),
  samarkand('samarkand', 39.6270, 66.9750),
  termez('termez', 37.2242, 67.2783),
  urgench('urgench', 41.5500, 60.6333);

  const PrayerCity(this.code, this.latitude, this.longitude);

  /// Stable storage code. Never rename an existing value.
  final String code;
  final double latitude;
  final double longitude;

  /// The city's civil time offset from UTC.
  Duration get utcOffset => const Duration(hours: 5);

  Coordinates get coordinates => Coordinates(latitude, longitude);

  static PrayerCity? fromCode(String? code) {
    for (final city in values) {
      if (city.code == code) return city;
    }
    return null;
  }
}
