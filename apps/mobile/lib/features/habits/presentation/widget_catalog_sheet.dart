/// The widget catalogue: what a new home widget can track.
///
/// Picking a kind opens the editor already set up for it — its own daily
/// amount, its unit and a name to start from — so setting a widget up is
/// two taps and a time, not a blank form.
///
/// The kinds are grouped under the life area they belong to and carry that
/// area's colour, because the list is long enough that an alphabet of
/// nineteen icons would be a wall rather than a choice. Group headings
/// reuse the module names the "all sections" sheet already shows, so the
/// same area is called the same thing everywhere.
library;

import 'package:flutter/material.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../domain/habit_kind.dart';
import 'habit_editor.dart';
import 'habit_kind_labels.dart';

/// One heading and the kinds under it. A null [title] renders the kinds
/// with no heading — used for the single "something else" tile, where a
/// heading would only repeat the tile below it.
class _CatalogGroup {
  const _CatalogGroup(this.title, this.kinds);

  final String? title;
  final List<HabitKind> kinds;
}

List<_CatalogGroup> _groups(AppLocalizations l10n) {
  return [
    _CatalogGroup(l10n.modulePrayer, const [
      HabitKind.zikr,
      HabitKind.dua,
      HabitKind.fasting,
    ]),
    _CatalogGroup(l10n.moduleQuran, const [
      HabitKind.quran,
      HabitKind.book,
    ]),
    _CatalogGroup(l10n.moduleHealth, const [
      HabitKind.sport,
      HabitKind.running,
      HabitKind.walk,
      HabitKind.water,
      HabitKind.diet,
    ]),
    _CatalogGroup(l10n.moduleWork, const [
      HabitKind.study,
      HabitKind.language,
    ]),
    _CatalogGroup(l10n.moduleFamily, const [
      HabitKind.family,
      HabitKind.charity,
    ]),
    _CatalogGroup(l10n.moduleMood, const [
      HabitKind.mood,
      HabitKind.journal,
    ]),
    _CatalogGroup(l10n.moduleSleep, const [
      HabitKind.sleep,
      HabitKind.earlyRise,
    ]),
    // Last, and alone: a widget for something the catalogue does not name.
    const _CatalogGroup(null, [HabitKind.custom]),
  ];
}

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
            for (final group in _groups(l10n)) ...[
              const SizedBox(height: KunimSpacing.md),
              if (group.title case final title?)
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              for (final kind in group.kinds) _KindTile(kind: kind, l10n: l10n),
            ],
          ],
        ),
      ),
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({required this.kind, required this.l10n});

  final HabitKind kind;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final name = habitKindName(l10n, kind);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: habitKindColor(kind),
        child: Icon(habitKindIcon(kind), color: Colors.white, size: 20),
      ),
      title: Text(name),
      subtitle: Text(habitAmount(l10n, kind, kind.dailyTarget)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () {
        final navigator = Navigator.of(context);
        // The editor opens on the root navigator, so the sheet has to be
        // closed first or it would sit on top of it.
        navigator.pop();
        showHabitEditor(
          navigator.context,
          kind: kind,
          title: kind == HabitKind.custom ? null : name,
        );
      },
    );
  }
}
