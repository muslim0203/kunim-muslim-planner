/// The account's own details: who the user is, not what they did.
///
/// Height lives here because it barely changes. WEIGHT deliberately does not:
/// it is a dated `health_logs` measurement, which is what makes the weight
/// chart possible. A copy here would go stale the day after it was set and
/// then disagree with the chart, so the profile screen reads the latest log
/// and writes an edit back as a log.
library;

class Profile {
  const Profile({
    required this.id,
    required this.email,
    this.displayName,
    this.nickname,
    this.birthYear,
    this.heightCm,
    this.avatarUrl,
    this.gender,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
      nickname: json['nickname'] as String?,
      birthYear: (json['birth_year'] as num?)?.toInt(),
      heightCm: (json['height_cm'] as num?)?.toInt(),
      avatarUrl: json['avatar_url'] as String?,
      gender: json['gender'] as String?,
    );
  }

  final String id;
  final String email;

  /// The name the user gives, in full ("ism sharifi"). Free text: a name is
  /// not the app's to validate beyond a length cap.
  final String? displayName;

  /// The handle others can see on the leaderboard. Lowercase and plain, so
  /// two handles cannot be confused for one another.
  final String? nickname;

  /// The year of birth, not the age. An age stored as a number is wrong by
  /// the next birthday; a year never is.
  final int? birthYear;
  final int? heightCm;
  final String? avatarUrl;
  final String? gender;

  /// Age in whole years, as of [today].
  ///
  /// Only the year is known, so this is the age the user reaches during
  /// [today]'s year — the honest precision for the data we hold.
  int? ageIn(DateTime today) =>
      birthYear == null ? null : ageFromBirthYear(birthYear!, today);

  /// The same rule for a year that has been typed but not saved yet.
  ///
  /// Returns null for a year that cannot be a birth year — in the future, or
  /// implying an age no one reaches — so the form shows nothing rather than
  /// a nonsense age while the user is still typing.
  static int? ageFromBirthYear(int birthYear, DateTime today) {
    final age = today.year - birthYear;
    return age < 0 || age > 150 ? null : age;
  }

  /// One or two letters for the avatar, taken from the name, else the
  /// handle, else the email. Never empty: a profile always has an email.
  String get initials {
    var source = [displayName, nickname, email]
        .firstWhere((value) => value != null && value.trim().isNotEmpty)!
        .trim();
    // Falling back to the email means the LOCAL part only: the domain is not
    // the user's name, and "zarif@b.com" reading as "ZC" (zarif + com) is
    // nobody's initials.
    final at = source.indexOf('@');
    if (at > 0) source = source.substring(0, at);

    final words = source
        .split(RegExp(r'[\s._-]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length >= 2) {
      return (words[0][0] + words[1][0]).toUpperCase();
    }
    final word = words.isEmpty ? source : words.first;
    return word.characters2.toUpperCase();
  }

  Profile copyWith({
    String? displayName,
    String? nickname,
    int? birthYear,
    int? heightCm,
    String? avatarUrl,
    String? gender,
  }) {
    return Profile(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      nickname: nickname ?? this.nickname,
      birthYear: birthYear ?? this.birthYear,
      heightCm: heightCm ?? this.heightCm,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gender: gender ?? this.gender,
    );
  }
}

extension on String {
  /// The first one or two characters, whichever the string has.
  String get characters2 => length >= 2 ? substring(0, 2) : substring(0, 1);
}
