/// Field helpers shared by the daily log repositories (mood, sleep, health,
/// family): notes and code lists are normalised the same way everywhere, and
/// always within the bounds the server validates.
library;

import 'dart:convert';

/// Server-side limit for every daily log `note`.
const int dailyLogMaxNoteLength = 2000;

/// Server-side limits for a tag/activity code list. Well above the size of
/// either vocabulary, so a server-side set union of two devices' lists stays
/// within it (the server also caps merged lists at this size).
const int dailyLogMaxCodes = 32;
const int dailyLogMaxCodeLength = 32;

final RegExp _codePattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// Trims [note]; blank becomes `null`. Throws [ArgumentError] past
/// [dailyLogMaxNoteLength] (the screen limits input, so this is a bug guard).
String? normalizeNote(String? note) {
  final trimmed = note?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.length > dailyLogMaxNoteLength) {
    throw ArgumentError.value(
        note,
        'note',
        'longer than '
            '$dailyLogMaxNoteLength characters');
  }
  return trimmed;
}

/// Orders [codes] like [known] (unknown but well-formed codes, e.g. from a
/// newer app version on another device, are kept at the end so an edit here
/// never drops them). Throws [ArgumentError] for malformed codes or more
/// than [dailyLogMaxCodes].
List<String> normalizeCodes(Iterable<String> codes, List<String> known) {
  final unique = codes.toSet();
  for (final code in unique) {
    if (code.length > dailyLogMaxCodeLength || !_codePattern.hasMatch(code)) {
      throw ArgumentError.value(code, 'codes', 'malformed code');
    }
  }
  final ordered = [
    for (final code in known)
      if (unique.contains(code)) code,
    ...(unique.difference(known.toSet()).toList()..sort()),
  ];
  if (ordered.length > dailyLogMaxCodes) {
    throw ArgumentError.value(ordered, 'codes', 'more than $dailyLogMaxCodes');
  }
  return ordered;
}

/// Reads a JSON array of codes stored in a text column. Anything unreadable
/// degrades to an empty list rather than breaking a screen.
List<String> decodeCodes(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded.whereType<String>().toList();
  } on FormatException {
    // Fall through.
  }
  return const [];
}

String encodeCodes(List<String> codes) => jsonEncode(codes);

/// [instant] truncated to a whole UTC minute, so a derived duration and the
/// millisecond wire timestamps can never disagree.
DateTime toUtcMinute(DateTime instant) {
  final ms = instant.toUtc().millisecondsSinceEpoch;
  return DateTime.fromMillisecondsSinceEpoch(
    ms - ms % Duration.millisecondsPerMinute,
    isUtc: true,
  );
}
