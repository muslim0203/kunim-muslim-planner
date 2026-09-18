/// Riverpod wiring for the boards.
///
/// Both boards are server state: they are fetched when the screen opens and
/// refetched after a change (a new friend, a removed one, joining the global
/// board). Nothing is cached locally — a board is other people's data, and
/// the app has no business keeping it on the device.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../data/social_api.dart';
import '../domain/board.dart';

/// Signed out, there is no board to fetch.
bool _signedIn(Ref ref) => ref.watch(authControllerProvider) is AuthSignedIn;

final friendsBoardProvider = FutureProvider.autoDispose<Board?>((ref) async {
  if (!_signedIn(ref)) return null;
  return ref.watch(socialApiProvider).friendsBoard();
});

final globalBoardProvider = FutureProvider.autoDispose<Board?>((ref) async {
  if (!_signedIn(ref)) return null;
  return ref.watch(socialApiProvider).globalBoard();
});

/// Invites, unfriending and joining the global board. Every method refreshes
/// the boards it can change, so the screen never shows a stale list.
class SocialController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  SocialApi get _api => ref.read(socialApiProvider);

  Future<InviteCode> createInvite() => _api.createInvite();

  /// Codes are shown and stored in upper case, so what the user typed is
  /// normalised here rather than in the transport.
  ///
  /// Throws [SocialApiException] when the code cannot be redeemed.
  Future<void> acceptInvite(String code) async {
    await _api.acceptInvite(code.trim().toUpperCase());
    ref.invalidate(friendsBoardProvider);
  }

  Future<void> removeFriend(String userId) async {
    await _api.removeFriend(userId);
    ref.invalidate(friendsBoardProvider);
  }

  /// Sets the name shown on a board, and joins or leaves the global one.
  Future<void> updateBoardProfile({
    String? nickname,
    bool? leaderboardOptIn,
  }) async {
    await _api.updateBoardProfile(
      // A nickname is lower case everywhere, so two names can never differ
      // only by case.
      nickname: nickname?.trim().toLowerCase(),
      leaderboardOptIn: leaderboardOptIn,
    );
    ref.invalidate(globalBoardProvider);
    ref.invalidate(friendsBoardProvider);
  }
}

final socialControllerProvider =
    NotifierProvider<SocialController, AsyncValue<void>>(
  SocialController.new,
);
