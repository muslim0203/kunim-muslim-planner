/// Derived task state that a screen needs but the Drift row itself
/// (`core/db/tables/tasks_table.dart`) does not carry as a column.
///
/// ADR-0002 conflict-matrix rule 8 (`docs/sync-conflict-matrix.md`):
/// `tasks.completed_at` is `max_wins` on the server and there is **no
/// synced `completed` boolean** — "done" is always derived as
/// `completedAt != null`. Never add a `completed` field to a sync payload.
/// When the user un-completes a task, the correct (and only) move is to
/// set `completedAt` to `null` locally and let the row sync normally, the
/// same as any other field. This surprises people the first time they hit
/// it, so it is worth spelling out: because the server keeps the **max**
/// of the two `completed_at` values across devices, an "uncomplete"
/// written on this device can still lose to an older "complete" recorded
/// on another device once the two rows merge. That is intentional — sync
/// must never turn a task back to "not done" — but it means "uncomplete"
/// is not guaranteed to stick if another device's completion is still in
/// flight.
library;

import 'package:kunim/core/db/app_database.dart';

/// Read-only derived properties of a [Task] row. Keeping these as an
/// extension (rather than duplicating fields on a wrapper class) means a
/// screen can use a plain `Task` everywhere and still get `isCompleted`/
/// `isOverdue` for free, with no risk of the derived value drifting out of
/// sync with the row it was computed from.
extension TaskStatus on Task {
  /// The ONLY source of truth for "done" — see the library doc comment.
  bool get isCompleted => completedAt != null;

  /// True when [dueDate] is in the past and the task is not completed. A
  /// completed task is never overdue, even if it was finished after its
  /// due date passed — overdue is a call to action, and a done task needs
  /// none.
  bool isOverdue({DateTime? now}) {
    final due = dueDate;
    if (due == null || isCompleted) return false;
    return due.isBefore(now ?? DateTime.now());
  }

  /// Soft-delete tombstone check (ADR-0002 §1: `deletedAt` is set, rows
  /// are never hard-deleted locally).
  bool get isDeleted => deletedAt != null;
}
