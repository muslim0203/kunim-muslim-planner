/// Tile text that never breaks a word in the middle.
///
/// The home grid packs four tiles across a phone, so a long label such as
/// "Хотиржамлик" has to shrink a little rather than hyphenate. Shared by the
/// widget grid and whatever else lays out narrow tiles.
library;

import 'package:flutter/material.dart';

/// Text that shrinks (down to [minShrink]) when its longest word would not
/// fit [maxWidth], so narrow tiles never break a word in the middle.
class FitWordText extends StatelessWidget {
  const FitWordText(
    this.text, {
    super.key,
    required this.maxWidth,
    required this.style,
    this.maxLines = 2,
  });

  /// Smallest scale that stays readable (a 12sp label becomes ~10sp).
  static const double minShrink = 0.85;

  /// Headroom below [maxWidth]: a word scaled to exactly the line width can
  /// still be broken by sub-pixel rounding in the text engine.
  static const double _fitMargin = 2;

  final String text;
  final double maxWidth;
  final TextStyle style;
  final int maxLines;

  /// Width of the widest single word in [text], as it would render.
  static double widestWord(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final resolved = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    var widest = 0.0;
    for (final word in text.split(RegExp(r'\s+'))) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: resolved),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return widest;
  }

  /// The style [text] renders with inside [maxWidth]: shrunk just enough for
  /// its widest word, but never below [minShrink].
  static TextStyle effectiveStyle(
    BuildContext context,
    String text,
    TextStyle style,
    double maxWidth,
  ) {
    final resolved = DefaultTextStyle.of(context).style.merge(style);
    final widest = widestWord(context, text, style);
    final target = maxWidth - _fitMargin;
    if (target <= 0 || widest <= target) return resolved;
    final factor = (target / widest).clamp(minShrink, 1.0);
    return resolved.copyWith(fontSize: (resolved.fontSize ?? 14) * factor);
  }

  /// Whether [text] fits [maxWidth] without breaking a word or needing more
  /// than [maxLines] lines.
  static bool fitsWithin(
    BuildContext context,
    String text,
    TextStyle style,
    double maxWidth, {
    required int maxLines,
  }) {
    if (widestWord(context, text, style) * minShrink > maxWidth - _fitMargin) {
      return false;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: effectiveStyle(context, text, style, maxWidth),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    return fits;
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: effectiveStyle(context, text, style, maxWidth),
    );
  }
}
