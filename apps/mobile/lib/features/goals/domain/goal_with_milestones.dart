/// The shape a goal-detail screen needs: a goal plus its live milestones,
/// combined reactively by `application/goals_providers.dart`
/// (`goalWithMilestonesProvider`).
library;

import '../../../core/db/app_database.dart' show Goal, Milestone;

class GoalWithMilestones {
  const GoalWithMilestones({required this.goal, required this.milestones});

  /// `null` when this goal has not synced to this device yet.
  /// `milestones.goal_id` is a loose reference with no SQL foreign key
  /// (see `goals_table.dart`'s class doc) — a milestone can legitimately
  /// exist locally before its parent goal has arrived from another
  /// device, so a screen must handle a `null` goal here rather than
  /// assume one always exists for a milestone list it can see.
  final Goal? goal;
  final List<Milestone> milestones;
}
