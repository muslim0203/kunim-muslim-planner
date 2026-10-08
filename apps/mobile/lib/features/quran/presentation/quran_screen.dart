/// The Qur'an index: pick a surah or a juz, or carry on where you stopped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../application/quran_providers.dart';
import '../domain/quran_models.dart';
import 'quran_reader_screen.dart';

class QuranScreen extends ConsumerWidget {
  const QuranScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.quranTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.quranSurahs),
              Tab(text: l10n.quranJuzs),
            ],
          ),
        ),
        body: Column(
          children: [
            const _ContinueCard(),
            Expanded(
              child: TabBarView(
                children: [
                  _SurahList(),
                  _JuzList(),
                ],
              ),
            ),
            const _SourceLine(),
          ],
        ),
      ),
    );
  }
}

void openMushaf(BuildContext context, int page) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => QuranReaderScreen(initialPage: page),
    ),
  );
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final position = ref.watch(quranPositionProvider).value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KunimSpacing.lg,
        KunimSpacing.md,
        KunimSpacing.lg,
        0,
      ),
      child: HeritageCard(
        onTap: () => openMushaf(context, position?.page ?? 1),
        child: Row(
          children: [
            Icon(
              Icons.auto_stories_rounded,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: KunimSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    position == null ? l10n.quranStart : l10n.quranContinue,
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    l10n.quranPageNumber(position?.page ?? 1),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _SurahList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surahs = ref.watch(quranSurahsProvider);

    return surahs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Failed(message: l10n.errorGeneric),
      data: (items) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: KunimSpacing.sm),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final surah = items[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Text(
                '${surah.number}',
                style: theme.textTheme.labelMedium,
              ),
            ),
            title: Text(surah.nameLatin),
            subtitle: Text(
              '${surah.revelation == Revelation.medinan ? l10n.quranMedinan : l10n.quranMeccan}'
              ' · ${l10n.quranAyahCount(surah.ayahCount)}'
              ' · ${l10n.quranPageNumber(surah.startPage)}',
            ),
            trailing: Text(
              surah.nameAr,
              textDirection: TextDirection.rtl,
              style: theme.textTheme.titleMedium,
            ),
            onTap: () => openMushaf(context, surah.startPage),
          );
        },
      ),
    );
  }
}

class _JuzList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final juzs = ref.watch(quranJuzsProvider);

    return juzs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Failed(message: l10n.errorGeneric),
      data: (items) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: KunimSpacing.sm),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final juz = items[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Text('${juz.number}', style: theme.textTheme.labelMedium),
            ),
            title: Text(l10n.quranJuzNumber(juz.number)),
            subtitle: Text(l10n.quranPageNumber(juz.startPage)),
            onTap: () => openMushaf(context, juz.startPage),
          );
        },
      ),
    );
  }
}

/// Tanzil's terms: wherever the text is shown, its source is named.
class _SourceLine extends ConsumerWidget {
  const _SourceLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final edition = ref.watch(quranEditionProvider).value;
    if (edition == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KunimSpacing.lg,
        KunimSpacing.xs,
        KunimSpacing.lg,
        KunimSpacing.md,
      ),
      child: Text(
        '${edition.edition} — ${edition.attribution}',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KunimSpacing.lg),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
