/// What the server's analyst sent back, as this build can use it.
///
/// The server holds no vocabulary of its own: it was told which areas this
/// device measured and which widget kinds this build can create, and it
/// drops anything outside that. This layer repeats the check rather than
/// trusting it, for one reason — a widget kind this build does not know
/// would be created as a plain `custom` widget, which is not what the
/// proposal said. A proposal that cannot be honoured exactly is dropped.
///
/// Nothing here is written anywhere. A proposal becomes a widget only when
/// the user taps accept, and then through the ordinary local write path
/// (`HabitMutationController`), never by the server.
library;

import '../../habits/domain/habit_kind.dart';
import '../../onboarding/domain/onboarding_answers.dart';

/// One area, in the model's words.
class AiAreaNote {
  const AiAreaNote({
    required this.area,
    required this.note,
    required this.priority,
  });

  final FocusArea area;
  final String note;

  /// 1 needs attention first, 3 is working. Used only to order the notes.
  final int priority;

  /// Returns null for an area slug this build does not know — the same
  /// choice the offline analysis makes for a widget kind it cannot place.
  static AiAreaNote? tryFromJson(Map<String, dynamic> json) {
    final area = FocusArea.fromSlug(json['area'] as String?);
    final note = (json['note'] as String?)?.trim();
    if (area == null || note == null || note.isEmpty) return null;
    final priority = (json['priority'] as num?)?.toInt() ?? 3;
    return AiAreaNote(
      area: area,
      note: note,
      priority: priority.clamp(1, 3),
    );
  }
}

/// A widget the model thinks is missing. Still only a suggestion here.
class AiWidgetProposal {
  const AiWidgetProposal({
    required this.kind,
    required this.title,
    required this.dailyTarget,
    required this.reason,
    this.reminderMinutes,
  });

  final HabitKind kind;

  /// The name as the model wrote it, in the user's language. Shown to the
  /// user before they accept, and used as the widget's title if they do.
  final String title;

  final int dailyTarget;
  final int? reminderMinutes;

  /// What in the numbers led to this. Shown under the title: a suggestion
  /// with no reason is advice from nowhere.
  final String reason;

  /// Returns null unless every part of the proposal is something this build
  /// can create exactly as described.
  static AiWidgetProposal? tryFromJson(Map<String, dynamic> json) {
    final kind = _knownKind(json['kind'] as String?);
    final title = (json['title'] as String?)?.trim();
    final target = (json['daily_target'] as num?)?.toInt();
    if (kind == null || title == null || title.isEmpty || target == null) {
      return null;
    }
    final reminder = (json['reminder_minutes'] as num?)?.toInt();
    return AiWidgetProposal(
      kind: kind,
      title: title,
      dailyTarget: target.clamp(1, 100000),
      reminderMinutes: reminder == null ? null : reminder.clamp(0, 1439),
      reason: (json['reason'] as String?)?.trim() ?? '',
    );
  }

  /// [HabitKind.fromCode] falls back to [HabitKind.custom], which would turn
  /// an unknown kind into a shapeless widget. Here an unknown kind must mean
  /// "drop it", so the lookup is strict.
  static HabitKind? _knownKind(String? code) {
    if (code == null) return null;
    for (final kind in HabitKind.values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

/// The analyst's whole answer.
class AiAnalysis {
  const AiAnalysis({
    required this.summary,
    this.areas = const [],
    this.widgets = const [],
  });

  final String summary;

  /// Most urgent first.
  final List<AiAreaNote> areas;
  final List<AiWidgetProposal> widgets;

  bool get isEmpty => summary.isEmpty && areas.isEmpty && widgets.isEmpty;

  factory AiAnalysis.fromJson(Map<String, dynamic> json) {
    final areas = <AiAreaNote>[
      for (final entry in _objects(json['areas']))
        if (AiAreaNote.tryFromJson(entry) case final note?) note,
    ]..sort((a, b) => a.priority.compareTo(b.priority));

    return AiAnalysis(
      summary: (json['summary'] as String?)?.trim() ?? '',
      areas: areas,
      widgets: [
        for (final entry in _objects(json['widgets']))
          if (AiWidgetProposal.tryFromJson(entry) case final widget?) widget,
      ],
    );
  }

  static Iterable<Map<String, dynamic>> _objects(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>();
  }
}

/// A stored proposal: the answer plus the id the accept/reject call needs.
class AiProposal {
  const AiProposal({
    required this.id,
    required this.analysis,
    this.model,
  });

  final String id;
  final AiAnalysis analysis;

  /// Which model answered, for the "how this was made" line. Null on an
  /// older row.
  final String? model;

  factory AiProposal.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    return AiProposal(
      id: json['id'] as String,
      analysis: AiAnalysis.fromJson(
        payload is Map<String, dynamic> ? payload : const {},
      ),
      model: json['model'] as String?,
    );
  }
}

/// What the user did with a proposal. The wire values the server stores.
enum AiProposalOutcome {
  accepted('accepted'),
  modified('modified'),
  rejected('rejected');

  const AiProposalOutcome(this.wire);

  final String wire;
}
