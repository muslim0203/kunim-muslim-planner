// Pure-Dart unit tests for `features/tasks/domain/top_three_selection.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/features/tasks/domain/top_three_selection.dart';

void main() {
  test('empty selection has no pins', () {
    expect(TopThreeSelection.empty.taskIds, isEmpty);
    expect(TopThreeSelection.empty.isEmpty, isTrue);
    expect(TopThreeSelection.empty.isFull, isFalse);
  });

  test('withPinned appends a new id', () {
    final selection = TopThreeSelection.empty.withPinned('a');
    expect(selection.taskIds, ['a']);
    expect(selection.contains('a'), isTrue);
  });

  test(
      'withPinned moves an already-pinned id to the end instead of duplicating',
      () {
    final selection = const TopThreeSelection(['a', 'b']).withPinned('a');
    expect(selection.taskIds, ['b', 'a']);
  });

  test('withPinned drops the oldest pin once at maxSize', () {
    final selection = const TopThreeSelection(['a', 'b', 'c']).withPinned('d');
    expect(selection.taskIds, ['b', 'c', 'd']);
    expect(selection.isFull, isTrue);
  });

  test('withUnpinned removes an id', () {
    final selection = const TopThreeSelection(['a', 'b']).withUnpinned('a');
    expect(selection.taskIds, ['b']);
  });

  test('withUnpinned is a no-op for an id that is not pinned', () {
    const selection = TopThreeSelection(['a']);
    expect(identical(selection.withUnpinned('z'), selection), isTrue);
  });

  test('reordered replaces the list outright', () {
    final selection = const TopThreeSelection(['a', 'b', 'c']).reordered(
      ['c', 'a', 'b'],
    );
    expect(selection.taskIds, ['c', 'a', 'b']);
  });

  test('maxSize is 3', () {
    expect(TopThreeSelection.maxSize, 3);
  });
}
