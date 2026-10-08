/// The mushaf reader: one page at a time, turned the way a printed mushaf is.
///
/// The Arabic on screen is the Tanzil Uthmani text, unchanged. The only thing
/// this file draws that is not in the text is the end-of-ayah marker (۝ with
/// the ayah's number), which is how the printed mushaf separates verses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../application/quran_providers.dart';
import '../domain/quran_models.dart';

/// Arabic-Indic digits, as the mushaf prints ayah numbers.
String arabicNumber(int value) {
  const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  return value
      .toString()
      .split('')
      .map((digit) => digits[int.parse(digit)])
      .join();
}

class QuranReaderScreen extends ConsumerStatefulWidget {
  const QuranReaderScreen({super.key, required this.initialPage});

  final int initialPage;

  @override
  ConsumerState<QuranReaderScreen> createState() => _QuranReaderScreenState();
}

class _QuranReaderScreenState extends ConsumerState<QuranReaderScreen> {
  late final PageController _controller;
  late int _page = Mushaf.clampPage(widget.initialPage);

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _page - 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _page = index + 1);
    // Remembered as the page turns: closing the app mid-read is the normal
    // way a reading ends, not an edge case.
    ref.read(quranPositionProvider.notifier).remember(index + 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.quranPageNumber(_page)),
        actions: [
          IconButton(
            tooltip: l10n.quranGoToPage,
            onPressed: _askForPage,
            icon: const Icon(Icons.numbers_rounded),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        // A mushaf opens right to left: swiping right goes forward.
        reverse: true,
        itemCount: Mushaf.pageCount,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) => _MushafPage(page: index + 1),
      ),
    );
  }

  Future<void> _askForPage() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: '$_page');
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.quranGoToPage),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l10n.quranPageOf(Mushaf.pageCount),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) =>
              Navigator.of(context).pop(int.tryParse(value.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.logCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(controller.text.trim())),
            child: Text(l10n.quranGo),
          ),
        ],
      ),
    );
    controller.dispose();
    if (page == null || !mounted) return;
    _controller.jumpToPage(Mushaf.clampPage(page) - 1);
  }
}

class _MushafPage extends ConsumerWidget {
  const _MushafPage({required this.page});

  final int page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final asyncPage = ref.watch(quranPageProvider(page));

    return asyncPage.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(KunimSpacing.lg),
          child: Text(l10n.errorGeneric, style: theme.textTheme.bodyMedium),
        ),
      ),
      data: (mushafPage) => _PageBody(page: mushafPage),
    );
  }
}

class _PageBody extends ConsumerWidget {
  const _PageBody({required this.page});

  final QuranPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final surahs = ref.watch(quranSurahsProvider).value;
    final names = [
      for (final number in page.surahNumbers)
        surahs == null || surahs.length < number
            ? '$number'
            : surahs[number - 1].nameAr,
    ].join(' · ');

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KunimSpacing.lg,
              KunimSpacing.sm,
              KunimSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.quranJuzNumber(page.juz),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  names,
                  textDirection: TextDirection.rtl,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
          const Divider(height: KunimSpacing.lg),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                KunimSpacing.lg,
                0,
                KunimSpacing.lg,
                KunimSpacing.xl,
              ),
              child: page.lines.isEmpty
                  ? MushafText(ayahs: page.ayahs)
                  : MushafPageText(page: page),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: KunimSpacing.sm),
            child: Text(
              '${page.number}',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The page exactly as the mushaf prints it: fifteen lines, each holding the
/// words that line holds in the print.
///
/// This is the whole point of the layout data. Someone who memorises from the
/// Madinah mushaf remembers where a verse sits — third line, left page — and
/// a reader that reflows the text to the screen width takes that away.
class MushafPageText extends StatelessWidget {
  const MushafPageText({super.key, required this.page});

  final QuranPage page;

  /// The size a line is measured at before it is scaled to the page width.
  static const double _baseFontSize = 26;

  /// Below this share of the width a line is centred rather than stretched:
  /// the print does not pull a surah's last few words across the page.
  static const double _justifyFrom = 0.55;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = TextStyle(
      fontSize: _baseFontSize,
      height: 1.6,
      color: theme.colorScheme.onSurface,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var widest = 0.0;
        for (final line in page.lines) {
          if (line.kind != LineKind.ayah) continue;
          final measured = _widthOf(context, _plainText(line), base);
          if (measured > widest) widest = measured;
        }
        // One size for the whole page, as the print uses: scaled just enough
        // for its longest line.
        final scale = widest == 0 ? 1.0 : (width / widest).clamp(0.4, 1.0);
        final style = base.copyWith(fontSize: _baseFontSize * scale);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final line in page.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _line(context, line, style, width),
              ),
          ],
        );
      },
    );
  }

  Widget _line(
    BuildContext context,
    MushafLine line,
    TextStyle style,
    double width,
  ) {
    final theme = Theme.of(context);
    switch (line.kind) {
      case LineKind.surah:
        return _SurahHeading(surah: line.surah, page: page);
      case LineKind.basmala:
        return Text(
          _basmalaOf(line.surah),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: style.copyWith(color: theme.colorScheme.onSurfaceVariant),
        );
      case LineKind.ayah:
        final natural = _widthOf(context, _plainText(line), style);
        final children = [
          for (final token in line.tokens)
            token.isEndMarker
                ? Text(
                    '۝${arabicNumber(token.ayahNumber)}',
                    style: style.copyWith(color: theme.colorScheme.primary),
                  )
                : Text(token.text, style: style),
        ];
        return Row(
          textDirection: TextDirection.rtl,
          mainAxisAlignment: natural >= width * _justifyFrom
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.center,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0 && natural < width * _justifyFrom)
                const SizedBox(width: 6),
              children[i],
            ],
          ],
        );
    }
  }

  /// The basmala words the print gives a line of their own, taken from the
  /// surah's own first ayah so nothing is typed in by hand.
  String _basmalaOf(int? surah) {
    final opening = page.ayahs.firstWhere(
      (ayah) => ayah.surah == surah && ayah.number == 1,
      orElse: () => page.ayahs.first,
    );
    final words = opening.text.split(RegExp(r'\s+'));
    final count = opening.basmalaWords;
    return count > 0 && words.length >= count
        ? words.take(count).join(' ')
        : '';
  }

  static String _plainText(MushafLine line) => [
        for (final token in line.tokens)
          token.isEndMarker ? '۝${arabicNumber(token.ayahNumber)}' : token.text,
      ].join(' ');

  static double _widthOf(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.rtl,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// The framed surah name the print puts above a surah's first line.
class _SurahHeading extends ConsumerWidget {
  const _SurahHeading({required this.surah, required this.page});

  final int? surah;
  final QuranPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final surahs = ref.watch(quranSurahsProvider).value;
    final name = surah == null || surahs == null || surahs.length < surah!
        ? ''
        : surahs[surah! - 1].nameAr;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        name,
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// The page's verses as one continuous right-to-left block — the fallback for
/// a database built without the printed layout.
class MushafText extends StatelessWidget {
  const MushafText({super.key, required this.ayahs});

  final List<Ayah> ayahs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markerColor = theme.colorScheme.primary;

    return Directionality(
      textDirection: TextDirection.rtl,
      // Plain text, not selectable: a selectable one swallows the horizontal
      // drag for its own selection handles, and turning the page is what a
      // horizontal drag means on a mushaf.
      child: Text.rich(
        TextSpan(
          children: [
            for (final ayah in ayahs) ...[
              TextSpan(text: ayah.text),
              TextSpan(
                text: ' ۝${arabicNumber(ayah.number)} ',
                style: TextStyle(color: markerColor),
              ),
            ],
          ],
        ),
        textAlign: TextAlign.justify,
        style: theme.textTheme.headlineSmall?.copyWith(
          height: 2.1,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
