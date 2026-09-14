import 'package:adhan_dart/adhan_dart.dart';
import 'package:flutter/foundation.dart';

import 'prayer_city.dart';

/// Calculation methods offered in the app. Stored by [code], never by the
/// `adhan_dart` enum name, so a package rename cannot corrupt saved settings.
enum PrayerMethod {
  muslimWorldLeague('mwl'),
  karachi('karachi'),
  egyptian('egyptian'),
  ummAlQura('umm_al_qura'),
  northAmerica('isna'),
  turkiye('turkiye'),
  russia('russia');

  const PrayerMethod(this.code);

  /// Stable storage code. Never rename an existing value.
  final String code;

  /// A fresh parameter object; callers may adjust it (e.g. the madhab).
  CalculationParameters parameters() => switch (this) {
        PrayerMethod.muslimWorldLeague =>
          CalculationMethodParameters.muslimWorldLeague(),
        PrayerMethod.karachi => CalculationMethodParameters.karachi(),
        PrayerMethod.egyptian => CalculationMethodParameters.egyptian(),
        PrayerMethod.ummAlQura => CalculationMethodParameters.ummAlQura(),
        PrayerMethod.northAmerica => CalculationMethodParameters.northAmerica(),
        PrayerMethod.turkiye => CalculationMethodParameters.turkiye(),
        PrayerMethod.russia => CalculationMethodParameters.russia(),
      };

  static PrayerMethod fromCode(String? code) => values.firstWhere(
        (method) => method.code == code,
        orElse: () => PrayerSettings.defaults.method,
      );
}

@immutable
class PrayerSettings {
  const PrayerSettings({
    this.city,
    required this.method,
    required this.madhab,
  });

  /// Hanafi is the madhab followed in Uzbekistan, so Asr defaults to it. The
  /// method is only a neutral starting point: it has NOT been checked against
  /// the official Uzbek timetable, and the prayer screen tells the user to
  /// compare and change it.
  static const PrayerSettings defaults = PrayerSettings(
    method: PrayerMethod.muslimWorldLeague,
    madhab: Madhab.hanafi,
  );

  /// `null` until the user picks a city; no times are shown before that.
  final PrayerCity? city;
  final PrayerMethod method;
  final Madhab madhab;

  PrayerSettings copyWith({
    PrayerCity? city,
    PrayerMethod? method,
    Madhab? madhab,
  }) {
    return PrayerSettings(
      city: city ?? this.city,
      method: method ?? this.method,
      madhab: madhab ?? this.madhab,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrayerSettings &&
      other.city == city &&
      other.method == method &&
      other.madhab == madhab;

  @override
  int get hashCode => Object.hash(city, method, madhab);
}
