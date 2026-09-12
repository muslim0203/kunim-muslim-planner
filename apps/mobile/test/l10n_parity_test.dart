import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// NOTE: this test cannot be executed on this machine (Flutter/Dart are not
// installed here — see apps/mobile/README.md). It is written to be correct
// against the Phase-0 skeleton and should be run with `flutter test` once
// Flutter is available (from the `apps/mobile` package root, so the
// relative ARB paths below resolve).
//
// This is the same parity rule enforced non-Flutter-side by
// `tool/check_l10n.mjs` (run with plain Node, no Flutter needed) — keep the
// two in sync if the ARB directory ever moves.
void main() {
  test('all ARB locale files declare exactly the same translation keys', () {
    const arbDir = 'lib/app/l10n';
    const localeFiles = [
      'app_en.arb',
      'app_ru.arb',
      'app_uz.arb',
      'app_uz_Cyrl.arb',
    ];

    final keysByFile = <String, Set<String>>{};

    for (final fileName in localeFiles) {
      final file = File('$arbDir/$fileName');
      expect(file.existsSync(), isTrue, reason: '$fileName must exist');

      final Map<String, dynamic> json =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      // Translation keys only: drop `@@...` locale metadata and `@key`
      // per-string metadata (descriptions/placeholders), which legitimately
      // only need to exist once, in the template file.
      final keys = json.keys.where((k) => !k.startsWith('@')).toSet();

      expect(keys, isNotEmpty, reason: '$fileName has no translation keys');
      keysByFile[fileName] = keys;
    }

    final referenceFile = localeFiles.first;
    final referenceKeys = keysByFile[referenceFile]!;

    for (final fileName in localeFiles.skip(1)) {
      final keys = keysByFile[fileName]!;

      final missing = referenceKeys.difference(keys);
      final extra = keys.difference(referenceKeys);

      expect(
        missing,
        isEmpty,
        reason: '$fileName is missing keys present in $referenceFile: $missing',
      );
      expect(
        extra,
        isEmpty,
        reason: '$fileName has keys not present in $referenceFile: $extra',
      );
    }
  });
}
