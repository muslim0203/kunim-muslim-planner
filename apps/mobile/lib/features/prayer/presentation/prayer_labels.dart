import 'package:adhan_dart/adhan_dart.dart' show Madhab;
import 'package:flutter/material.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../domain/daily_prayer_times.dart';
import '../domain/prayer_city.dart';
import '../domain/prayer_settings.dart';

/// Localized names, icons and formatting for the prayer module, shared by
/// the prayer screen, the home prayer strip and settings.
abstract final class PrayerLabels {
  static String prayer(AppLocalizations l10n, PrayerKind kind) {
    return switch (kind) {
      PrayerKind.fajr => l10n.prayerFajr,
      PrayerKind.sunrise => l10n.prayerSunrise,
      PrayerKind.dhuhr => l10n.prayerDhuhr,
      PrayerKind.asr => l10n.prayerAsr,
      PrayerKind.maghrib => l10n.prayerMaghrib,
      PrayerKind.isha => l10n.prayerIsha,
    };
  }

  static IconData icon(PrayerKind kind) {
    return switch (kind) {
      PrayerKind.fajr => Icons.wb_twilight_outlined,
      PrayerKind.sunrise => Icons.wb_sunny_outlined,
      PrayerKind.dhuhr => Icons.light_mode_outlined,
      PrayerKind.asr => Icons.sunny_snowing,
      PrayerKind.maghrib => Icons.nights_stay_outlined,
      PrayerKind.isha => Icons.dark_mode_outlined,
    };
  }

  static String city(AppLocalizations l10n, PrayerCity city) {
    return switch (city) {
      PrayerCity.tashkent => l10n.cityTashkent,
      PrayerCity.nurafshon => l10n.cityNurafshon,
      PrayerCity.andijan => l10n.cityAndijan,
      PrayerCity.bukhara => l10n.cityBukhara,
      PrayerCity.fergana => l10n.cityFergana,
      PrayerCity.guliston => l10n.cityGuliston,
      PrayerCity.jizzakh => l10n.cityJizzakh,
      PrayerCity.namangan => l10n.cityNamangan,
      PrayerCity.navoiy => l10n.cityNavoiy,
      PrayerCity.nukus => l10n.cityNukus,
      PrayerCity.qarshi => l10n.cityQarshi,
      PrayerCity.samarkand => l10n.citySamarkand,
      PrayerCity.termez => l10n.cityTermez,
      PrayerCity.urgench => l10n.cityUrgench,
    };
  }

  static String method(AppLocalizations l10n, PrayerMethod method) {
    return switch (method) {
      PrayerMethod.muslimWorldLeague => l10n.prayerMethodMwl,
      PrayerMethod.karachi => l10n.prayerMethodKarachi,
      PrayerMethod.egyptian => l10n.prayerMethodEgyptian,
      PrayerMethod.ummAlQura => l10n.prayerMethodUmmAlQura,
      PrayerMethod.northAmerica => l10n.prayerMethodIsna,
      PrayerMethod.turkiye => l10n.prayerMethodTurkiye,
      PrayerMethod.russia => l10n.prayerMethodRussia,
    };
  }

  static String madhab(AppLocalizations l10n, Madhab madhab) {
    return switch (madhab) {
      Madhab.hanafi => l10n.madhabHanafi,
      Madhab.shafi => l10n.madhabShafi,
    };
  }

  /// 24-hour time, as prayer timetables are printed.
  static String time(BuildContext context, DateTime time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: time.hour, minute: time.minute),
      alwaysUse24HourFormat: true,
    );
  }

  /// "in 2 h 15 min", rounded up so it never reads 0 before the time.
  static String countdown(AppLocalizations l10n, Duration left) {
    final minutes = (left.inSeconds / 60).ceil().clamp(0, 24 * 60);
    final hours = minutes ~/ 60;
    return hours > 0
        ? l10n.prayerInHoursMinutes(hours, minutes % 60)
        : l10n.prayerInMinutes(minutes);
  }
}
