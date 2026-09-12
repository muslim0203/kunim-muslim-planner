/// The phase-2 "Home'da Top-3" rule (`docs/plan.md` §12 phase table:
/// "Home'da Top-3 (qo'lda)"). "Qo'lda" means **manual** — the user
/// explicitly picks (and can reorder) up to three tasks to feature on the
/// home screen, as opposed to an algorithm scoring every task. This file
/// models exactly that: an explicit, user-chosen, ordered selection.
///
/// The AI-driven successor ("offline Smart Day/Top-3 (ustuvorlik/dedlayn
/// bo'yicha qoida)" mentioned elsewhere in the plan, and the fully
/// AI-driven version) is **phase 7** work (`docs/plan.md` §12: "AI: chat,
/// planner, reschedule, recs, memory, RAG ... offline fallback Smart
/// Day/Top-3"). It does not belong in this task — `task_ordering.dart`'s
/// `compareForTodayList` is the closest phase-2 has to a rule-based
/// ordering, and it is deliberately just a default sort for the full
/// list, never a replacement for the user's manual picks here.
///
/// Persistence note: there is no column on `Tasks`
/// (`core/db/tables/tasks_table.dart`) to flag/order a task as pinned, and
/// `core/db` is not owned by this task. Rather than inventing one here,
/// the manual selection is modeled as this plain, storage-agnostic value
/// type; `data/task_top_three_store.dart` persists it locally using the
/// existing generic `KeyValue` table (see that file's doc comment for
/// why that is the right place, and what a future synced version would
/// need instead).
library;

/// An ordered set of at most [maxSize] pinned task ids — the user's
/// manual Top-3. Order matters (index 0 is shown first); membership is
/// deduplicated (pinning an already-pinned id moves it rather than
/// duplicating it).
class TopThreeSelection {
  const TopThreeSelection(this.taskIds);

  static const empty = TopThreeSelection(<String>[]);

  /// Phase-2 hard cap per the plan's "Top-3" naming. Not configurable —
  /// if a later phase wants more than three pins, that is a product
  /// decision for that phase, not a parameter of this one.
  static const maxSize = 3;

  final List<String> taskIds;

  bool get isFull => taskIds.length >= maxSize;

  bool get isEmpty => taskIds.isEmpty;

  bool contains(String taskId) => taskIds.contains(taskId);

  /// Returns a new selection with [taskId] pinned at the end. If
  /// [taskId] is already pinned, it is moved to the end instead of
  /// duplicated. If the selection is already at [maxSize] (and [taskId]
  /// is new), the oldest pin (index 0) is dropped to make room — pinning
  /// is "the 3 most recently chosen", not a queue that silently refuses
  /// new picks.
  TopThreeSelection withPinned(String taskId) {
    final withoutId = taskIds.where((id) => id != taskId).toList();
    final next = [...withoutId, taskId];
    if (next.length > maxSize) {
      next.removeAt(0);
    }
    return TopThreeSelection(next);
  }

  /// Returns a new selection with [taskId] removed, if present.
  TopThreeSelection withUnpinned(String taskId) {
    if (!contains(taskId)) return this;
    return TopThreeSelection(taskIds.where((id) => id != taskId).toList());
  }

  /// Returns a new selection with the pins in exactly [orderedIds]'s
  /// order. Callers (a future drag-and-drop screen) are expected to pass
  /// a permutation of the current [taskIds]; this type does not validate
  /// that, since it has no access to which ids are otherwise valid.
  TopThreeSelection reordered(List<String> orderedIds) {
    return TopThreeSelection(orderedIds);
  }
}
