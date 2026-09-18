// The leaderboard: signed out it asks for an account; signed in it lists the
// board, adds a friend by code and joins the global board.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kunim/app/l10n/gen/app_localizations.dart';
import 'package:kunim/core/auth/auth_controller.dart';
import 'package:kunim/features/social/data/social_api.dart';
import 'package:kunim/features/social/domain/board.dart';
import 'package:kunim/features/social/presentation/leaderboard_screen.dart';

Future<void> _pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A signed-in session without touching secure storage or the network.
class _SignedIn extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(
        userId: '11111111-1111-4111-8111-111111111111',
        email: 'aziza@example.com',
      );
}

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthSignedOut();
}

class FakeSocialApi implements SocialApi {
  FakeSocialApi({Board? friends, Board? global})
      : friends = friends ?? const Board(entries: [], myRank: null),
        global = global ?? const Board(entries: [], myRank: null);

  Board friends;
  Board global;
  SocialErrorKind? acceptError;
  SocialErrorKind? profileError;

  String? acceptedCode;
  String? nickname;
  bool? optIn;
  String? removedFriend;
  int inviteCalls = 0;

  @override
  Future<InviteCode> createInvite() async {
    inviteCalls++;
    return InviteCode(
      code: 'ABCD2345',
      expiresAt: DateTime(2026, 9, 25),
    );
  }

  @override
  Future<void> acceptInvite(String code) async {
    if (acceptError != null) throw SocialApiException(acceptError!);
    acceptedCode = code;
  }

  @override
  Future<Board> friendsBoard() async => friends;

  @override
  Future<Board> globalBoard() async => global;

  @override
  Future<void> removeFriend(String userId) async => removedFriend = userId;

  @override
  Future<void> updateBoardProfile({
    String? nickname,
    bool? leaderboardOptIn,
  }) async {
    if (profileError != null) throw SocialApiException(profileError!);
    this.nickname = nickname;
    optIn = leaderboardOptIn;
  }
}

const _me = BoardEntry(
  userId: '11111111-1111-4111-8111-111111111111',
  name: 'aziza',
  pointsWeek: 120,
  pointsTotal: 900,
  isMe: true,
);
const _friend = BoardEntry(
  userId: '22222222-2222-4222-8222-222222222222',
  name: 'anvar',
  pointsWeek: 200,
  pointsTotal: 500,
  isMe: false,
);

void main() {
  late FakeSocialApi api;

  setUp(() => api = FakeSocialApi());

  Future<AppLocalizations> pumpBoard(
    WidgetTester tester, {
    bool signedIn = true,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialApiProvider.overrideWithValue(api),
          authControllerProvider
              .overrideWith(signedIn ? _SignedIn.new : _SignedOut.new),
        ],
        child: MaterialApp(
          locale: const Locale('uz'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LeaderboardScreen(),
        ),
      ),
    );
    await _pumpFrames(tester);
    return AppLocalizations.of(tester.element(find.byType(LeaderboardScreen)));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 3);
  }

  testWidgets('signed out, it asks for an account', (tester) async {
    final l10n = await pumpBoard(tester, signedIn: false);

    expect(find.text(l10n.socialSignedOut), findsOneWidget);
    expect(find.text(l10n.socialTabFriends), findsNothing);
    await unmount(tester);
  });

  testWidgets('the friends board lists everyone, best week first', (
    tester,
  ) async {
    api.friends = const Board(entries: [_friend, _me], myRank: 2);

    final l10n = await pumpBoard(tester);

    expect(find.text('anvar'), findsOneWidget);
    expect(find.text('aziza'), findsOneWidget);
    expect(find.text(l10n.socialMyRank(2)), findsOneWidget);
    expect(find.text(l10n.statsPointsWeek(200)), findsOneWidget);
    expect(find.text(l10n.socialPointsTotal(900)), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('with no friends yet it says so and offers the code sheet', (
    tester,
  ) async {
    api.friends = const Board(entries: [_me], myRank: 1);

    final l10n = await pumpBoard(tester);
    expect(find.text(l10n.socialFriendsEmpty), findsOneWidget);

    await tester.tap(find.text(l10n.socialAddFriend));
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.socialGetCode));
    await _pumpFrames(tester);

    expect(api.inviteCalls, 1);
    expect(find.text('ABCD2345'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a friend is added by code', (tester) async {
    api.friends = const Board(entries: [_me], myRank: 1);
    final l10n = await pumpBoard(tester);

    await tester.tap(find.text(l10n.socialAddFriend));
    await _pumpFrames(tester);
    await tester.enterText(find.byType(TextField).last, 'abcd2345');
    await _pumpFrames(tester, 2);
    await tester.tap(find.widgetWithText(FilledButton, l10n.socialSendCode));
    await _pumpFrames(tester);

    // The code is sent the way the server stores it.
    expect(api.acceptedCode, 'ABCD2345');
    expect(find.text(l10n.socialFriendAdded), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a code the server refuses is reported in place', (tester) async {
    api.friends = const Board(entries: [_me], myRank: 1);
    api.acceptError = SocialErrorKind.codeSpent;
    final l10n = await pumpBoard(tester);

    await tester.tap(find.text(l10n.socialAddFriend));
    await _pumpFrames(tester);
    await tester.enterText(find.byType(TextField).last, 'ABCD2345');
    await _pumpFrames(tester, 2);
    await tester.tap(find.widgetWithText(FilledButton, l10n.socialSendCode));
    await _pumpFrames(tester);

    expect(find.text(l10n.socialErrorCodeSpent), findsOneWidget);
    expect(find.text(l10n.socialFriendAdded), findsNothing);
    await unmount(tester);
  });

  testWidgets('the global board asks for a nickname before listing you', (
    tester,
  ) async {
    api.global = const Board(entries: [], myRank: null);
    final l10n = await pumpBoard(tester);

    await tester.tap(find.text(l10n.socialTabGlobal));
    await _pumpFrames(tester);
    expect(find.text(l10n.socialJoinTitle), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, l10n.socialNicknameLabel),
      'aziza',
    );
    await _pumpFrames(tester, 2);
    await tester.tap(find.widgetWithText(FilledButton, l10n.socialJoin));
    await _pumpFrames(tester);

    expect(api.nickname, 'aziza');
    expect(api.optIn, isTrue);
    await unmount(tester);
  });

  testWidgets('a taken nickname is reported in place', (tester) async {
    api.profileError = SocialErrorKind.nicknameTaken;
    final l10n = await pumpBoard(tester);

    await tester.tap(find.text(l10n.socialTabGlobal));
    await _pumpFrames(tester);
    await tester.enterText(
      find.widgetWithText(TextField, l10n.socialNicknameLabel),
      'aziza',
    );
    await _pumpFrames(tester, 2);
    await tester.tap(find.widgetWithText(FilledButton, l10n.socialJoin));
    await _pumpFrames(tester);

    expect(find.text(l10n.socialErrorNicknameTaken), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('removing a friend asks first', (tester) async {
    api.friends = const Board(entries: [_friend, _me], myRank: 2);
    final l10n = await pumpBoard(tester);

    await tester.tap(find.byTooltip(l10n.socialRemoveFriend));
    await _pumpFrames(tester);
    expect(find.text(l10n.socialRemoveConfirm), findsOneWidget);
    await tester
        .tap(find.widgetWithText(FilledButton, l10n.socialRemoveFriend));
    await _pumpFrames(tester);

    expect(api.removedFriend, _friend.userId);
    await unmount(tester);
  });
}
