/// How far a widget has come towards its total, and when it would finish at
/// the current daily amount.
///
/// Pure arithmetic over what is already stored: the logged amounts and the
/// widget's own numbers. Nothing here estimates effort or invents a pace —
/// the projection is simply "what is left, divided by the daily amount".
library;

import 'local_day.dart';

class HabitProgress {
  const HabitProgress({
    required this.done,
    required this.total,
    required this.perDay,
  });

  /// Everything logged for this widget so far.
  final int done;

  /// The amount that finishes it, or `null` for an open-ended widget.
  final int? total;

  /// The daily amount (`habits.target_count`).
  final int perDay;

  /// `null` when the widget is open-ended.
  int? get remaining {
    final total = this.total;
    if (total == null) return null;
    final left = total - done;
    return left < 0 ? 0 : left;
  }

  /// 0..1, or `null` when the widget is open-ended.
  double? get ratio {
    final total = this.total;
    if (total == null || total <= 0) return null;
    final value = done / total;
    return value > 1 ? 1 : value;
  }

  bool get isFinished => remaining == 0;

  /// Days still needed at [perDay] a day, or `null` when that cannot be
  /// projected (an open-ended widget, or one with no daily amount).
  int? get daysLeft {
    final remaining = this.remaining;
    if (remaining == null || perDay <= 0) return null;
    return (remaining + perDay - 1) ~/ perDay;
  }

  /// The day the widget would finish on, counting [today] as the first day
  /// of work. `null` when [daysLeft] is; [today] itself when it is done.
  LocalDay? finishDay(LocalDay today) {
    final days = daysLeft;
    if (days == null) return null;
    return days == 0 ? today : today.addDays(days - 1);
  }
}
