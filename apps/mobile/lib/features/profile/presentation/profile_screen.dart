/// "Hisob ma'lumotlari": the account's own details.
///
/// Everything here is optional. The app works without a name, a handle, a
/// birth year or a height, so the screen never demands one — it only offers
/// the fields and saves what is filled in.
///
/// Weight is shown here but stored as a `health_logs` measurement, the same
/// row the health screen and the weight chart use. See
/// `application/profile_providers.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../application/profile_providers.dart';
import '../data/profile_api.dart';
import '../domain/profile.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider);

    // Read the three cases by hand rather than with `when`.
    //
    // Riverpod retries a failed provider on its own, and while a retry is in
    // flight the state is `AsyncLoading` *carrying* the error — so `when`
    // would show the spinner again, and a user with no connection would sit
    // in front of a circle that never stops. An error wins over loading
    // here; a value wins over both, so a failed refresh keeps the form the
    // user was looking at instead of replacing it with a message.
    final value = profile.value;
    final error = profile.error;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: switch ((value, error)) {
        (final Profile loaded, _) => _ProfileForm(profile: loaded),
        (_, final Object failure) => _ProfileError(
            message: failure is ProfileApiException
                ? _messageFor(l10n, failure.kind)
                : l10n.profileErrorNetwork,
            onRetry: () => ref.invalidate(profileProvider),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

String _messageFor(AppLocalizations l10n, ProfileErrorKind kind) {
  return switch (kind) {
    ProfileErrorKind.network => l10n.profileErrorNetwork,
    ProfileErrorKind.unauthorized => l10n.profileErrorSignedOut,
    ProfileErrorKind.nicknameTaken => l10n.profileErrorNicknameTaken,
    ProfileErrorKind.invalid => l10n.profileErrorInvalid,
  };
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KunimSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: KunimSpacing.lg),
            FilledButton(onPressed: onRetry, child: Text(l10n.profileRetry)),
          ],
        ),
      ),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final TextEditingController _name;
  late final TextEditingController _nickname;
  late final TextEditingController _birthYear;
  late final TextEditingController _height;
  final TextEditingController _weight = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _name = TextEditingController(text: profile.displayName ?? '');
    _nickname = TextEditingController(text: profile.nickname ?? '');
    _birthYear = TextEditingController(
      text: profile.birthYear?.toString() ?? '',
    );
    _height = TextEditingController(text: profile.heightCm?.toString() ?? '');
    // The age under the year follows what is typed, not what was saved: a
    // user entering a year for the first time should see the age it implies
    // before committing to it, not after.
    _birthYear.addListener(_onBirthYearChanged);
  }

  void _onBirthYearChanged() => setState(() {});

  @override
  void dispose() {
    _birthYear.removeListener(_onBirthYearChanged);
    _name.dispose();
    _nickname.dispose();
    _birthYear.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final latestWeight = ref.watch(latestWeightProvider).value;
    if (_weight.text.isEmpty && latestWeight != null) {
      _weight.text = _trimZero(latestWeight);
    }

    final typedYear = int.tryParse(_birthYear.text.trim());
    final age = typedYear == null
        ? null
        : Profile.ageFromBirthYear(typedYear, DateTime.now());

    return ListView(
      padding: const EdgeInsets.all(KunimSpacing.lg),
      children: [
        Center(
          child: Column(
            children: [
              _InitialsAvatar(initials: widget.profile.initials),
              const SizedBox(height: KunimSpacing.md),
              Text(widget.profile.email, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: KunimSpacing.xl),
        HeritageCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field(
                controller: _name,
                label: l10n.profileFullName,
                hint: l10n.profileFullNameHint,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: KunimSpacing.lg),
              _Field(
                controller: _nickname,
                label: l10n.profileUsername,
                // The rule is helper text, not a hint: a hint lives inside
                // the single-line input box and is cut off at larger text
                // scales, exactly where someone is most likely to need it.
                helper: l10n.profileUsernameRule,
                prefix: '@',
                // The server accepts lowercase letters, digits and
                // underscores only, so the field refuses anything else as it
                // is typed rather than failing on save.
                formatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-z0-9_]')),
                  LengthLimitingTextInputFormatter(24),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: KunimSpacing.lg),
        HeritageCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field(
                controller: _birthYear,
                label: l10n.profileBirthYear,
                hint: l10n.profileBirthYearHint,
                keyboardType: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                // The year is stored, never the age: an age is wrong by the
                // next birthday.
                helper: age == null ? null : l10n.profileAgeNow(age),
              ),
              const SizedBox(height: KunimSpacing.lg),
              _Field(
                controller: _height,
                label: l10n.profileHeight,
                hint: l10n.profileHeightHint,
                keyboardType: TextInputType.number,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
              ),
              const SizedBox(height: KunimSpacing.lg),
              _Field(
                controller: _weight,
                label: l10n.profileWeight,
                hint: l10n.profileWeightHint,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                helper: l10n.profileWeightHelper,
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: KunimSpacing.lg),
          Text(
            _error!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: KunimSpacing.xl),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? l10n.profileSaving : l10n.profileSave),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final name = _name.text.trim();
      final nickname = _nickname.text.trim();
      final year = int.tryParse(_birthYear.text.trim());
      final height = int.tryParse(_height.text.trim());

      await ref.read(profileApiProvider).update(
            displayName: name.isEmpty ? null : name,
            clearDisplayName: name.isEmpty,
            nickname: nickname.isEmpty ? null : nickname,
            clearNickname: nickname.isEmpty,
            birthYear: year,
            clearBirthYear: _birthYear.text.trim().isEmpty,
            heightCm: height,
            clearHeight: _height.text.trim().isEmpty,
          );

      // Weight goes to the health log, not the profile.
      final weight = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
      if (weight != null) {
        await ref.read(weightWriterProvider)(weight);
      }

      ref.invalidate(profileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.profileSaved)),
      );
    } on ProfileApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(l10n, error.kind));
    } on ArgumentError {
      // `HealthLogRepository` rejects an implausible weight.
      if (!mounted) return;
      setState(() => _error = l10n.profileErrorInvalid);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _trimZero(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.prefix,
    this.keyboardType,
    this.formatters,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final String? prefix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        prefixText: prefix,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// A letter avatar.
///
/// A photo needs an upload endpoint and somewhere to put the file, neither of
/// which exists yet; initials give every account a recognisable mark today
/// and leave the picture as a later, separate piece of work.
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: AppLocalizations.of(context).profileAvatarLabel,
      child: CircleAvatar(
        radius: 44,
        backgroundColor: scheme.primaryContainer,
        child: Text(
          initials,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
