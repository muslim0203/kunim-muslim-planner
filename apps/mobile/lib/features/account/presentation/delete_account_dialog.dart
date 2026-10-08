/// Confirms account deletion with the password
/// (`AuthController.deleteAccount`) or, for an account signed into with
/// Google, with Google (`AuthController.deleteAccountWithGoogle`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/auth/auth_api.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/google_sign_in_client.dart';

class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  ConsumerState<DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() => setState(() {});

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final google = ref.watch(googleSignInClientProvider).isAvailable;

    return AlertDialog(
      title: Text(l10n.accountDeleteTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.accountDeleteBody),
            const SizedBox(height: KunimSpacing.md),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: l10n.authPasswordLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            if (google) ...[
              const SizedBox(height: KunimSpacing.md),
              Text(
                l10n.accountDeleteGoogleHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: KunimSpacing.xs),
              OutlinedButton(
                key: const Key('delete-with-google'),
                onPressed: _busy ? null : _deleteWithGoogle,
                child: Text(l10n.accountDeleteWithGoogle),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: KunimSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.logCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _busy || _password.text.isEmpty ? null : _delete,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.accountDeleteConfirm),
        ),
      ],
    );
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(password: _password.text);
    } on AuthApiException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _messageFor(l10n, error.kind,
              wrongProof: l10n.accountDeleteWrongPassword);
        });
      }
      return;
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(l10n.accountDeleted)));
  }

  Future<void> _deleteWithGoogle() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    var deleted = false;
    try {
      deleted = await ref
          .read(authControllerProvider.notifier)
          .deleteAccountWithGoogle();
    } on GoogleSignInClientException {
      error = l10n.authErrorGoogle;
    } on AuthApiException catch (e) {
      error = _messageFor(l10n, e.kind,
          wrongProof: l10n.accountDeleteWrongGoogleAccount);
    }
    if (!deleted) {
      // Closing Google's picker leaves the dialog as it was, without an error.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
      return;
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(l10n.accountDeleted)));
  }

  static String _messageFor(
    AppLocalizations l10n,
    AuthErrorKind kind, {
    required String wrongProof,
  }) {
    return switch (kind) {
      AuthErrorKind.invalidCredentials => wrongProof,
      AuthErrorKind.network => l10n.authErrorNetwork,
      AuthErrorKind.rateLimited => l10n.authErrorRateLimited,
      AuthErrorKind.invalidInput || AuthErrorKind.server => l10n.errorGeneric,
    };
  }
}
