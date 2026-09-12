// Application-layer wiring tests: `taskRepositoryProvider` must be the
// place `SyncTriggerScheduler.onLocalWrite` gets a real caller
// (`core/sync/sync_triggers.dart` has none until this feature wires it
// up), `todayTasksProvider` must apply the domain ordering reactively, and
// the mutation controllers must expose loading/error `AsyncValue` state
// around the repository calls.
//
// `syncTriggerSchedulerProvider` is overridden with a plain,
// never-`start()`ed `SyncTriggerScheduler` so these tests never touch a
// real `Timer`/`Connectivity`/`AppLifecycleListener` — the same reason
// `test/sync/sync_engine_triggers_test.dart` constructs the scheduler
// directly instead of going through the provider.
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/core/db/app_database.dart';
import 'package:kunim/core/sync/sync_triggers.dart';
import 'package:kunim/features/tasks/application/task_category_mutation_controller.dart';
import 'package:kunim/features/tasks/application/task_category_providers.dart';
import 'package:kunim/features/tasks/application/task_mutation_controller.dart';
import 'package:kunim/features/tasks/application/task_providers.dart';
import 'package:kunim/features/tasks/application/top_three_mutation_controller.dart';
import 'package:kunim/features/tasks/application/top_three_providers.dart';
import 'package:kunim/features/tasks/domain/task_status.dart';

/// Riverpod 3 auto-disposes every provider by default. A bare
/// `firstValue(container, p)` therefore creates the provider with no
/// listener, and it can be torn down again before the underlying Drift
/// `watch()` stream has emitted — the future then never completes and the
/// test times out. Holding a subscription for the duration of the await is
/// the documented way to keep it alive.
Future<T> firstValue<T>(ProviderContainer c, StreamProvider<T> p) async {
  final sub = c.listen(p, (_, __) {});
  try {
    return await c.read(p.future);
  } finally {
    sub.close();
  }
}

void main() {
  late AppDatabase db;
  late List<bool> syncCalls;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    syncCalls = [];
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncTriggerSchedulerProvider.overrideWithValue(
          SyncTriggerScheduler(
            runSync: ({bool force = false}) async {
              syncCalls.add(force);
            },
            policy: const SyncTriggerPolicy(localWriteThreshold: 1),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
      'creating a task through the mutation controller triggers the '
      'local-write sync scheduler', () async {
    final controller = container.read(taskMutationControllerProvider.notifier);

    final task = await controller.createTask(title: 'Read Qur\'an');

    expect(task, isNotNull);
    expect(
      syncCalls,
      [false],
      reason: 'onLocalWrite must have reached the injected scheduler',
    );
  });

  test('allTasksProvider reflects a created task reactively', () async {
    final controller = container.read(taskMutationControllerProvider.notifier);

    var seenLengths = <int>[];
    final sub = container.listen(
      allTasksProvider,
      (previous, next) {
        next.whenData((tasks) => seenLengths.add(tasks.length));
      },
      fireImmediately: true,
    );

    await pumpEventQueue();
    await controller.createTask(title: 'Task 1');
    await pumpEventQueue();

    expect(seenLengths, contains(1));
    sub.close();
  });

  test('todayTasksProvider only includes tasks due today or overdue', () async {
    final controller = container.read(taskMutationControllerProvider.notifier);
    final now = DateTime.now();

    await controller.createTask(title: 'Due today', dueDate: now);
    await controller.createTask(
      title: 'Due next month',
      dueDate: now.add(const Duration(days: 30)),
    );

    // Let the reactive stream settle.
    await pumpEventQueue();
    final today = await firstValue(container, todayTasksProvider);

    expect(today.map((t) => t.title), ['Due today']);
  });

  test('completing then un-completing a task through the controller', () async {
    final controller = container.read(taskMutationControllerProvider.notifier);
    final created = await controller.createTask(title: 'Toggle me');

    final completed = await controller.completeTask(created!.id);
    expect(completed!.isCompleted, isTrue);

    final uncompleted = await controller.uncompleteTask(created.id);
    expect(uncompleted!.isCompleted, isFalse);
  });

  test('deleteTask removes the task from allTasksProvider', () async {
    final controller = container.read(taskMutationControllerProvider.notifier);
    final created = await controller.createTask(title: 'Temporary');

    await controller.deleteTask(created!.id);
    await pumpEventQueue();

    final all = await firstValue(container, allTasksProvider);
    expect(all.where((t) => t.id == created.id), isEmpty);
  });

  test('category mutation controller creates and reorders categories',
      () async {
    final controller =
        container.read(taskCategoryMutationControllerProvider.notifier);

    final a = await controller.createCategory(name: 'A');
    final b = await controller.createCategory(name: 'B');
    expect(a, isNotNull);
    expect(b, isNotNull);

    await controller.reorderCategories([b!.id, a!.id]);
    await pumpEventQueue();

    final categories = await firstValue(container, allTaskCategoriesProvider);
    expect(categories.map((c) => c.id), [b.id, a.id]);
  });

  test(
      'top-three mutation controller pins tasks and resolves them via '
      'topThreeTasksProvider', () async {
    final taskController =
        container.read(taskMutationControllerProvider.notifier);
    final topThreeController =
        container.read(topThreeMutationControllerProvider.notifier);

    final task = await taskController.createTask(title: 'Pinned task');
    await topThreeController.pin(task!.id);
    await pumpEventQueue();

    // Let both underlying streams (selection + all tasks) settle before
    // reading the derived provider.
    await firstValue(container, topThreeSelectionProvider);
    await firstValue(container, allTasksProvider);

    final resolved = container.read(topThreeTasksProvider);
    expect(
      resolved.value?.map((t) => t.id),
      [task.id],
    );
  });

  test('a pin for a task that no longer exists is silently dropped', () async {
    final topThreeController =
        container.read(topThreeMutationControllerProvider.notifier);

    await topThreeController.pin('does-not-exist');
    await pumpEventQueue();

    await firstValue(container, topThreeSelectionProvider);
    await firstValue(container, allTasksProvider);

    final resolved = container.read(topThreeTasksProvider);
    expect(resolved.value, isEmpty);
  });
}
