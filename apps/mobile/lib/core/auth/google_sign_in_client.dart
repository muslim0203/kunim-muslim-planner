/// Google Sign-In on the device, reduced to the one thing the API needs: an
/// ID token for `/auth/google` (or to confirm deleting the account).
///
/// The token's audience must be one of the server's `GOOGLE_CLIENT_IDS`.
/// Android puts the `serverClientId` (the *web* OAuth client) there; iOS
/// additionally needs its own iOS client id. Both are build-time settings:
/// ```
/// flutter run \
///   --dart-define=KUNIM_GOOGLE_SERVER_CLIENT_ID=<web client id> \
///   --dart-define=KUNIM_GOOGLE_IOS_CLIENT_ID=<ios client id>
/// ```
/// Without a server client id the app hides the Google button.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

const String kunimGoogleServerClientId = String.fromEnvironment(
  'KUNIM_GOOGLE_SERVER_CLIENT_ID',
);
const String kunimGoogleIosClientId = String.fromEnvironment(
  'KUNIM_GOOGLE_IOS_CLIENT_ID',
);

/// Why no ID token came back.
enum GoogleSignInFailure {
  /// The user closed the Google sheet. Not an error worth showing.
  canceled,

  /// Google Sign-In is not set up in this build, or failed on the device.
  failed,
}

class GoogleSignInClientException implements Exception {
  const GoogleSignInClientException(this.failure);

  final GoogleSignInFailure failure;

  @override
  String toString() => 'GoogleSignInClientException($failure)';
}

abstract interface class GoogleSignInClient {
  /// Whether this build can sign in with Google at all.
  bool get isAvailable;

  /// Shows Google's account picker and returns a fresh ID token. Throws
  /// [GoogleSignInClientException].
  Future<String> idToken();

  /// Forgets the Google account chosen on this device, so the next sign-in
  /// asks again instead of silently reusing it.
  Future<void> signOut();
}

class PluginGoogleSignInClient implements GoogleSignInClient {
  PluginGoogleSignInClient({
    required String serverClientId,
    String iosClientId = '',
  })  : _serverClientId = serverClientId,
        _iosClientId = iosClientId;

  final String _serverClientId;
  final String _iosClientId;
  Future<void>? _initialized;

  GoogleSignIn get _plugin => GoogleSignIn.instance;

  @override
  bool get isAvailable => _serverClientId.isNotEmpty;

  Future<void> _initialize() {
    return _initialized ??= _plugin
        .initialize(
      clientId:
          defaultTargetPlatform == TargetPlatform.iOS && _iosClientId.isNotEmpty
              ? _iosClientId
              : null,
      serverClientId: _serverClientId,
    )
        .catchError((Object error) {
      // A failed setup is retried on the next attempt, not cached.
      _initialized = null;
      throw error;
    });
  }

  @override
  Future<String> idToken() async {
    if (!isAvailable) {
      throw const GoogleSignInClientException(GoogleSignInFailure.failed);
    }
    try {
      await _initialize();
      if (!_plugin.supportsAuthenticate()) {
        throw const GoogleSignInClientException(GoogleSignInFailure.failed);
      }
      final account = await _plugin.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const GoogleSignInClientException(GoogleSignInFailure.failed);
      }
      return token;
    } on GoogleSignInException catch (error) {
      debugPrint('Google sign-in failed: ${error.code}');
      throw GoogleSignInClientException(
        error.code == GoogleSignInExceptionCode.canceled
            ? GoogleSignInFailure.canceled
            : GoogleSignInFailure.failed,
      );
    }
  }

  @override
  Future<void> signOut() async {
    if (!isAvailable) return;
    try {
      await _initialize();
      await _plugin.signOut();
    } catch (error) {
      debugPrint('Google sign-out failed: ${error.runtimeType}');
    }
  }
}

final googleSignInClientProvider = Provider<GoogleSignInClient>((ref) {
  return PluginGoogleSignInClient(
    serverClientId: kunimGoogleServerClientId,
    iosClientId: kunimGoogleIosClientId,
  );
});
