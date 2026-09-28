/// The widget catalogue: what a new home widget can track.
///
/// Picking a kind opens the editor already set up for it — its own daily
/// amount, its unit and a name to start from — so setting a widget up is
/// two taps and a time, not a blank form.
library;

import 'package:flutter/material.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../domain/habit_kind.dart';
import 'habit_editor.dart';
import 'habit_kind_labels.dart';

Future<void> showWidgetCatalog(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const WidgetCatalogSheet(),
  );
}

class WidgetCatalogSheet extends StatelessWidget {
  const WidgetCatalogSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          KunimSpacing.lg,
          0,
          KunimSpacing.lg,
          KunimSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.habitCatalogTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: KunimSpacing.sm),
            for (final kind in HabitKind.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: habitKindColor(kind),
                  child: Icon(
                    habitKindIcon(kind),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: Text(habitKindName(l10n, kind)),
                subtitle: Text(habitAmount(l10n, kind, kind.dailyTarget)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  final name = habitKindName(l10n, kind);
                  final navigator = Navigator.of(context);
                  // The editor opens on the root navigator, so the sheet
                  // has to be closed first or it would sit on top of it.
                  navigator.pop();
                  showHabitEditor(
                    navigator.context,
                    kind: kind,
                    title: kind == HabitKind.custom ? null : name,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
