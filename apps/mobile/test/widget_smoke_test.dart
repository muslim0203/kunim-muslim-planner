import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kunim/app/app.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';

// NOTE: this test cannot be executed on this machine (Flutter is not
// installed here — see apps/mobile/README.md). It is written to be
// correct against the Phase-0 skeleton and should be run with
// `flutter test` once Flutter is available.
void main() {
  testWidgets('launches to the Home placeholder with 5 nav destinations',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KunimApp()));
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(Scaffold).first);
    final l10n = AppLocalizations.of(context);

    // The Home branch is the initial location, so its localized title
    // should appear both in the app bar and the bottom navigation bar.
    expect(find.text(l10n.navHome), findsWidgets);

    // All five bottom-nav destinations are present.
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(l10n.navDay), findsOneWidget);
    expect(find.text(l10n.navStats), findsOneWidget);
    expect(find.text(l10n.navAi), findsOneWidget);
    expect(find.text(l10n.navSettings), findsOneWidget);
  });
}
