/// Account: sign in or create an account to back up and sync this device's
/// data, or, signed in, see the sync state and sign out. The app stays fully
/// usable without an account.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/auth/auth_api.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/network/error_mapper.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import 'delete_account_dialog.dart';
import 'password_reset_sheet.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAccount)),
      body: switch (auth) {
        AuthRestoring() => const Center(child: CircularProgressIndicator()),
        AuthSignedIn(:final email) => _SignedInView(email: email),
        AuthSignedOut(:final sessionExpired) =>
          _SignInForm(sessionExpired: sessionExpired),
      },
    );
  }
}

/// A short sync state line: "Syncing…", "Last synced at 14:05", "Offline…".
String syncStatusLabel(BuildContext context, SyncStatus status) {
  final l10n = AppLocalizations.of(context);
  return switch (status) {
    SyncIdle() => l10n.syncNeverSynced,
    SyncRunning() || SyncSkippedBusy() => l10n.syncSyncing,
    SyncSuccess(:final completedAt) => l10n.syncLastSynced(
        MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay.fromDateTime(completedAt.toLocal()),
          alwaysUse24HourFormat: true,
        ),
      ),
    SyncFailed(failure: NetworkFailure() || TimeoutFailure()) =>
      l10n.syncOffline,
    SyncFailed() || SyncSkippedBackoff() => l10n.syncFailed,
  };
}

class _SignedInView extends ConsumerWidget {
  const _SignedInView({required this.email});

  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final status = ref.watch(syncStatusProvider);
    final running = status is SyncRunning;

    return ListView(
      padding: const EdgeInsets.all(KunimSpacing.lg),
      children: [
        HeritageCard(
          child: Row(
            children: [
              Icon(
                Icons.account_circle_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: KunimSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.accountSignedIn,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KunimSpacing.md),
        HeritageCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sync_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: KunimSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.accountSyncTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KunimSpacing.xs),
              Text(
                syncStatusLabel(context, status),
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: KunimSpacing.md),
              FilledButton.tonalIcon(
                onPressed: running
                    ? null
                    : () => ref
                        .read(syncStatusProvider.notifier)
                        .runNow(force: true),
                icon: const Icon(Icons.sync_rounded),
                label: Text(l10n.syncNow),
              ),
            ],
          ),
        ),
        const SizedBox(height: KunimSpacing.xl),
        OutlinedButton.icon(
          onPressed: () => _confirmSignOut(context, ref),
          icon: const Icon(Icons.logout_rounded),
          label: Text(l10n.authSignOut),
        ),
        const SizedBox(height: KunimSpacing.sm),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const DeleteAccountDialog(),
          ),
          icon: const Icon(Icons.delete_forever_outlined),
          label: Text(l10n.accountDelete),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.accountSignOutConfirmTitle),
        content: Text(l10n.accountSignOutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.logCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.authSignOut),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}

class _SignInForm extends ConsumerStatefulWidget {
  const _SignInForm({required this.sessionExpired});

  final bool sessionExpired;

  @override
  ConsumerState<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends ConsumerState<_SignInForm> {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static const int _minPasswordLength = 8;

  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final errorStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.error,
    );

    return ListView(
      padding: const EdgeInsets.all(KunimSpacing.lg),
      children: [
        Text(
          _signUp ? l10n.authSignUpTitle : l10n.authSignInTitle,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: KunimSpacing.xs),
        Text(
          l10n.accountSignInPrompt,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (widget.sessionExpired && _error == null) ...[
          const SizedBox(height: KunimSpacing.md),
          Text(l10n.authErrorSessionExpired, style: errorStyle),
        ],
        const SizedBox(height: KunimSpacing.lg),
        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.authEmailLabel,
            prefixIcon: const Icon(Icons.alternate_email_rounded),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: KunimSpacing.md),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          textInputAction:
              _signUp ? TextInputAction.next : TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.authPasswordLabel,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_signUp) ...[
          const SizedBox(height: KunimSpacing.md),
          TextField(
            controller: _confirm,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l10n.authConfirmPasswordLabel,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (!_signUp)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => showPasswordResetSheet(context, email: _email.text),
              child: Text(l10n.authForgotPassword),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: KunimSpacing.md),
          Text(_error!, style: errorStyle),
        ],
        const SizedBox(height: KunimSpacing.lg),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_signUp ? l10n.authSignUpButton : l10n.authSignInButton),
        ),
        const SizedBox(height: KunimSpacing.sm),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _signUp = !_signUp;
                    _error = null;
                  }),
          child: Text(
            _signUp
                ? '${l10n.authHaveAccount} ${l10n.authSignInTitle}'
                : '${l10n.authNoAccount} ${l10n.authSignUpTitle}',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final email = _email.text.trim();
    final password = _password.text;
    final String? invalid;
    if (!_emailPattern.hasMatch(email)) {
      invalid = l10n.authErrorInvalidEmail;
    } else if (password.length < _minPasswordLength) {
      invalid = l10n.authErrorPasswordTooShort;
    } else if (_signUp && password != _confirm.text) {
      invalid = l10n.authErrorPasswordsMismatch;
    } else {
      invalid = null;
    }
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(authControllerProvider.notifier);
    try {
      if (_signUp) {
        await controller.signUp(
          email: email,
          password: password,
          locale: ref.read(appSettingsProvider).language.code,
        );
      } else {
        await controller.signIn(email: email, password: password);
      }
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = _messageFor(l10n, error.kind));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _messageFor(AppLocalizations l10n, AuthErrorKind kind) {
    return switch (kind) {
      AuthErrorKind.invalidCredentials => l10n.authErrorInvalidCredentials,
      AuthErrorKind.network => l10n.authErrorNetwork,
      AuthErrorKind.rateLimited => l10n.authErrorRateLimited,
      AuthErrorKind.invalidInput || AuthErrorKind.server => l10n.errorGeneric,
    };
  }
}
