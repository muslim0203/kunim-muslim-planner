/// Resetting a forgotten password: ask for a code, then set the new password
/// with it.
///
/// Two steps in one sheet, because the code arrives in a mail the user reads
/// on the same phone: leaving the app open at the second step is what makes
/// the round trip short.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/auth/auth_api.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/settings/app_settings.dart';

/// Opens the sheet, starting from [email] when the sign-in form had one.
Future<void> showPasswordResetSheet(BuildContext context, {String? email}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => PasswordResetSheet(email: email),
  );
}

class PasswordResetSheet extends ConsumerStatefulWidget {
  const PasswordResetSheet({super.key, this.email});

  final String? email;

  @override
  ConsumerState<PasswordResetSheet> createState() => _PasswordResetSheetState();
}

class _PasswordResetSheetState extends ConsumerState<PasswordResetSheet> {
  static const int _codeLength = 6;
  static const int _minPasswordLength = 8;

  late final TextEditingController _email =
      TextEditingController(text: widget.email ?? '');
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();

  /// False while asking for the code, true once one has been sent.
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    for (final field in [_email, _code, _password]) {
      field.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
            Text(l10n.authForgotTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: KunimSpacing.xs),
            Text(
              l10n.authForgotBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: KunimSpacing.lg),
            TextField(
              controller: _email,
              enabled: !_busy && !_codeSent,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: l10n.authEmailLabel,
                prefixIcon: const Icon(Icons.alternate_email_rounded),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: KunimSpacing.md),
              TextField(
                controller: _code,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_codeLength),
                ],
                decoration: InputDecoration(
                  labelText: l10n.authResetCodeLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: KunimSpacing.md),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: l10n.authResetNewPassword,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            if (_notice != null) ...[
              const SizedBox(height: KunimSpacing.md),
              Text(
                _notice!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: KunimSpacing.md),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: KunimSpacing.lg),
            FilledButton(
              onPressed: _busy || !_canSubmit ? null : _submit,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _codeSent ? l10n.authResetSubmit : l10n.authForgotSend,
                    ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: KunimSpacing.sm),
              TextButton(
                onPressed: _busy ? null : _sendCode,
                child: Text(l10n.authForgotSend),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _canSubmit {
    if (!_codeSent) return _email.text.trim().isNotEmpty;
    return _code.text.trim().length == _codeLength &&
        _password.text.length >= _minPasswordLength;
  }

  Future<void> _submit() => _codeSent ? _reset() : _sendCode();

  Future<void> _sendCode() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).requestPasswordReset(
            email: _email.text,
            locale: ref.read(appSettingsProvider).language.code,
          );
    } on AuthApiException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _messageFor(l10n, error.kind);
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _codeSent = true;
        _notice = l10n.authForgotSent;
      });
    }
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).resetPassword(
            email: _email.text,
            code: _code.text,
            newPassword: _password.text,
          );
    } on AuthApiException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _messageFor(l10n, error.kind);
        });
      }
      return;
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(l10n.authResetDone)));
  }

  static String _messageFor(AppLocalizations l10n, AuthErrorKind kind) {
    return switch (kind) {
      // The server answers 400 for a code that is wrong, spent or expired.
      AuthErrorKind.invalidInput => l10n.authResetErrorCode,
      AuthErrorKind.invalidCredentials => l10n.authResetErrorCode,
      AuthErrorKind.rateLimited => l10n.authErrorRateLimited,
      AuthErrorKind.network => l10n.authErrorNetwork,
      AuthErrorKind.server => l10n.errorGeneric,
    };
  }
}
