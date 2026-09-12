/// The "today's list" membership rule and ordering for the tasks feature.
/// Pure Dart, no Drift/Riverpod dependency beyond the generated [Task] row
/// type, so it is trivial to unit test and reuse from any provider.
library;

import 'package:kunim/core/db/app_database.dart';

import 'task_status.dart';

/// True when [task] belongs on a "today" list: due today or overdue, and
/// not soft-deleted. Tasks with no [Task.dueDate] are never part of
/// "today" — they are undated and belong in a general/backlog view
/// instead, not a screen this task does not build.
///
/// A task whose [Task.categoryId] points at a category that has not
/// synced yet or was deleted elsewhere (`tasks_table.dart` — no SQL FK by
/// design) is unaffected by this check: it only looks at [Task] columns,
/// never joins against `TaskCategories`, so a dangling category reference
/// neither crashes this function nor hides the task from the list.
bool isInTodayList(Task task, {DateTime? now}) {
  if (task.isDeleted) return false;
  final due = task.dueDate;
  if (due == null) return false;
  final today = now ?? DateTime.now();
  final endOfToday =
      DateTime(today.year, today.month, today.day, 23, 59, 59, 999);
  return !due.isAfter(endOfToday);
}

/// Sort order for a "today" list:
/// 1. Not completed and overdue, earliest due date first (most urgent).
/// 2. Not completed and due today, higher [TaskPriority] first, then
///    earliest due time, then oldest-created first (stable tie-break).
/// 3. Completed, most recently completed first (so a freshly finished
///    task is visible for a moment before sinking to the bottom).
///
/// This is the plain rule-based ordering the plan calls "ustuvorlik/
/// dedlayn bo'yicha qoida" (`docs/plan.md` line ~206) for the offline
/// Smart Day/Top-3 fallback — it is NOT the manual Top-3 selection itself
/// (see `top_three_selection.dart`), just the default ordering for the
/// full today's list a screen would show underneath/around the pinned
/// Top-3.
int compareForTodayList(Task a, Task b, {DateTime? now}) {
  final reference = now ?? DateTime.now();

  int group(Task t) {
    if (t.isCompleted) return 2;
    if (t.isOverdue(now: reference)) return 0;
    return 1;
  }

  final groupA = group(a);
  final groupB = group(b);
  if (groupA != groupB) return groupA.compareTo(groupB);

  if (groupA == 2) {
    final completedA = a.completedAt;
    final completedB = b.completedAt;
    if (completedA == null || completedB == null) {
      // Should not happen (group 2 implies isCompleted), but keep sorting
      // total rather than throwing.
      return 0;
    }
    return completedB.compareTo(completedA);
  }

  final priorityCompare = b.priority.index.compareTo(a.priority.index);
  if (priorityCompare != 0) return priorityCompare;

  final dueA = a.dueDate;
  final dueB = b.dueDate;
  if (dueA != null && dueB != null) {
    final dueCompare = dueA.compareTo(dueB);
    if (dueCompare != 0) return dueCompare;
  } else if (dueA != null || dueB != null) {
    // A null due date here would mean the task failed `isInTodayList`, so
    // this branch is unreachable for a properly filtered list — kept only
    // so this comparator stays safe to use standalone.
    return dueA == null ? 1 : -1;
  }

  return a.createdAt.compareTo(b.createdAt);
}

/// Filters [tasks] to `isInTodayList` and sorts them with
/// [compareForTodayList]. Does not mutate [tasks].
List<Task> todayTasksFrom(List<Task> tasks, {DateTime? now}) {
  final filtered = tasks.where((t) => isInTodayList(t, now: now)).toList()
    ..sort((a, b) => compareForTodayList(a, b, now: now));
  return filtered;
}
