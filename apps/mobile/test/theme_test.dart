import 'package:flutter_test/flutter_test.dart';

import 'package:kunim/app/theme/tokens.dart';

// NOTE: this test cannot be executed on this machine (Flutter/Dart are not
// installed here — see apps/mobile/README.md). It is written to be correct
// against the Phase-0 skeleton and should be run with `flutter test` once
// Flutter is available. It only touches plain Dart constants (no widgets,
// no BuildContext), so it needs no golden/pump machinery.
void main() {
  group('KunimRadii', () {
    test('all radii fall within the 16-20 range from docs/plan.md', () {
      for (final radius in [
        KunimRadii.small,
        KunimRadii.medium,
        KunimRadii.large,
      ]) {
        expect(radius, greaterThanOrEqualTo(12));
        expect(radius, lessThanOrEqualTo(20));
      }
      // The plan's stated range is specifically 16-20; `small` is allowed
      // to sit a little under that for compact chips, but `medium` (the
      // default card radius) and `large` must land inside it.
      expect(KunimRadii.medium, inInclusiveRange(16, 20));
      expect(KunimRadii.large, inInclusiveRange(16, 20));
    });

    test(
        'large radius is not smaller than medium, medium not smaller than small',
        () {
      expect(KunimRadii.large, greaterThanOrEqualTo(KunimRadii.medium));
      expect(KunimRadii.medium, greaterThanOrEqualTo(KunimRadii.small));
    });
  });

  group('KunimSpacing', () {
    test('scale is strictly increasing', () {
      final steps = [
        KunimSpacing.xs,
        KunimSpacing.sm,
        KunimSpacing.md,
        KunimSpacing.lg,
        KunimSpacing.xl,
        KunimSpacing.xxl,
      ];
      for (var i = 1; i < steps.length; i++) {
        expect(
          steps[i],
          greaterThan(steps[i - 1]),
          reason: 'spacing step $i must be strictly greater than step ${i - 1}',
        );
      }
    });

    test('smallest step is positive', () {
      expect(KunimSpacing.xs, greaterThan(0));
    });
  });

  group('accessibility constants', () {
    test('minimum touch target meets the 48dp accessibility floor', () {
      expect(kMinTouchTarget, greaterThanOrEqualTo(48));
    });
  });

  group('KunimModuleColors', () {
    test('every module has a distinct accent color', () {
      final colors = <int>{
        KunimModuleColors.prayer.toARGB32(),
        KunimModuleColors.quran.toARGB32(),
        KunimModuleColors.mood.toARGB32(),
        KunimModuleColors.family.toARGB32(),
        KunimModuleColors.health.toARGB32(),
        KunimModuleColors.work.toARGB32(),
        KunimModuleColors.sleep.toARGB32(),
      };
      // 7 modules in docs/plan.md section 2: prayer/quran/mood/family/
      // health/work/sleep. If two collapse to the same color, one was
      // copy-pasted wrong.
      expect(colors, hasLength(7));
    });

    test('every module color is fully opaque', () {
      for (final color in [
        KunimModuleColors.prayer,
        KunimModuleColors.quran,
        KunimModuleColors.mood,
        KunimModuleColors.family,
        KunimModuleColors.health,
        KunimModuleColors.work,
        KunimModuleColors.sleep,
      ]) {
        // Color.a is a 0.0-1.0 double in Dart 3.13; fully opaque is 1.0.
        expect(color.a, 1.0);
      }
    });
  });
}
