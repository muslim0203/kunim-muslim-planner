/// What the account is asked once, when it is created.
///
/// The answers are slugs, not free text: the suggestion rules key off them,
/// and the server stores them as given (`/users/me`). A slug this build does
/// not know is still carried — the answer belongs to the user, and a newer
/// app may have offered it.
library;

/// What the user does with most of their day.
///
/// The list is deliberately short. Its only job is to let the rules guess
/// what a day is already missing — someone at a desk is not short of
/// thinking time but of movement; someone on their feet all day is the
/// other way round — so two occupations that imply the same day belong
/// together rather than apart.
enum Occupation {
  student('student'),
  teacher('teacher'),
  office('office'),
  business('business'),
  medical('medical'),
  it('it'),
  labour('labour'),
  driver('driver'),
  homemaker('homemaker'),
  religious('religious'),
  other('other');

  const Occupation(this.slug);

  final String slug;

  static Occupation? fromSlug(String? slug) {
    for (final value in values) {
      if (value.slug == slug) return value;
    }
    return null;
  }
}

/// Something the user wants in their day. One interest becomes at most one
/// widget; what the widget tracks is [Interest.kindSlug].
enum Interest {
  quran('quran'),
  zikr('zikr'),
  book('book'),
  study('study'),
  sport('sport'),
  water('water'),
  family('family'),
  sleep('sleep'),
  mood('mood');

  const Interest(this.slug);

  final String slug;

  static Interest? fromSlug(String? slug) {
    for (final value in values) {
      if (value.slug == slug) return value;
    }
    return null;
  }
}

/// A life area the user says is weak and wants to strengthen.
///
/// Kept apart from [Interest] on purpose: "I like reading" and "my reading
/// has slipped" are different statements, and the second one outranks the
/// first when the day does not have room for both.
enum FocusArea {
  prayer('prayer'),
  quran('quran'),
  health('health'),
  family('family'),
  work('work'),
  study('study'),
  sleep('sleep'),
  mood('mood');

  const FocusArea(this.slug);

  final String slug;

  static FocusArea? fromSlug(String? slug) {
    for (final value in values) {
      if (value.slug == slug) return value;
    }
    return null;
  }
}

/// The minutes a day the user says they can give. Offered as a few honest
/// choices rather than a slider: nobody knows whether their day holds 37
/// minutes, and the number only has to be right enough to size a plan.
abstract final class DailyBudget {
  static const List<int> choices = [15, 30, 60, 90];
  static const int fallback = 30;

  /// Keeps an answer inside what a day can hold, whatever a newer client or
  /// a hand-edited profile sends.
  static int clamp(int? minutes) =>
      minutes == null ? fallback : minutes.clamp(5, 600);
}

/// Everything the onboarding asked, as the rules see it.
class OnboardingAnswers {
  const OnboardingAnswers({
    this.occupation,
    this.interests = const {},
    this.focusAreas = const {},
    this.dailyMinutes,
  });

  /// Rebuilds the answers from stored slugs, dropping any this build does
  /// not know — the profile keeps them, the rules just cannot use them.
  factory OnboardingAnswers.fromSlugs({
    String? occupation,
    List<String> interests = const [],
    List<String> focusAreas = const [],
    int? dailyMinutes,
  }) {
    return OnboardingAnswers(
      occupation: Occupation.fromSlug(occupation),
      interests: {
        for (final slug in interests)
          if (Interest.fromSlug(slug) case final interest?) interest,
      },
      focusAreas: {
        for (final slug in focusAreas)
          if (FocusArea.fromSlug(slug) case final area?) area,
      },
      dailyMinutes: dailyMinutes,
    );
  }

  final Occupation? occupation;
  final Set<Interest> interests;
  final Set<FocusArea> focusAreas;

  /// Null while the question has not been answered; [budget] is what the
  /// rules use.
  final int? dailyMinutes;

  int get budget => DailyBudget.clamp(dailyMinutes);

  /// Whether anything at all was answered. Nothing answered means nothing
  /// to suggest — the app does not guess a life from an empty form.
  bool get isEmpty =>
      occupation == null && interests.isEmpty && focusAreas.isEmpty;

  OnboardingAnswers copyWith({
    Occupation? occupation,
    Set<Interest>? interests,
    Set<FocusArea>? focusAreas,
    int? dailyMinutes,
  }) {
    return OnboardingAnswers(
      occupation: occupation ?? this.occupation,
      interests: interests ?? this.interests,
      focusAreas: focusAreas ?? this.focusAreas,
      dailyMinutes: dailyMinutes ?? this.dailyMinutes,
    );
  }
}
