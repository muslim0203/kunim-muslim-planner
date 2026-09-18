/// "Reyting": the friends board and the global one.
///
/// Both are server state and need an account. A friend is added by
/// exchanging a short code; the global board lists only people who chose a
/// nickname and turned it on. An email is never shown — the server does not
/// send one.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/l10n/gen/app_localizations.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../shared/widgets/kunim_widgets.dart';
import '../application/social_providers.dart';
import '../data/social_api.dart';
import '../domain/board.dart';

enum BoardKind { friends, global }

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  BoardKind _kind = BoardKind.friends;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signedIn = ref.watch(authControllerProvider) is AuthSignedIn;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.socialTitle)),
      body: signedIn ? _board(context, l10n) : _SignInPrompt(),
    );
  }

  Widget _board(BuildContext context, AppLocalizations l10n) {
    final board = _kind == BoardKind.friends
        ? ref.watch(friendsBoardProvider)
        : ref.watch(globalBoardProvider);

    return ListView(
      padding: const EdgeInsets.all(KunimSpacing.lg),
      children: [
        SegmentedButton<BoardKind>(
          segments: [
            ButtonSegment(
              value: BoardKind.friends,
              label: Text(l10n.socialTabFriends),
            ),
            ButtonSegment(
              value: BoardKind.global,
              label: Text(l10n.socialTabGlobal),
            ),
          ],
          selected: {_kind},
          onSelectionChanged: (selection) =>
              setState(() => _kind = selection.first),
        ),
        const SizedBox(height: KunimSpacing.lg),
        ...switch (board) {
          AsyncData(:final value) when value != null => _entries(l10n, value),
          AsyncError() => [
              HeritageCard(child: Text(l10n.errorGeneric)),
            ],
          _ => [const Center(child: CircularProgressIndicator())],
        },
      ],
    );
  }

  String? _gap(Board board) => _gapLine(AppLocalizations.of(context), board);

  List<Widget> _entries(AppLocalizations l10n, Board board) {
    final others = [
      for (final entry in board.entries)
        if (!entry.isMe) entry
    ];

    return [
      if (_kind == BoardKind.global && board.myRank == null) ...[
        _JoinGlobalCard(),
        const SizedBox(height: KunimSpacing.lg),
      ],
      if (board.myRank != null) ...[
        Text(
          l10n.socialMyRank(board.myRank!),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (_gap(board) case final gap?) ...[
          const SizedBox(height: KunimSpacing.xs),
          Text(
            gap,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
        const SizedBox(height: KunimSpacing.sm),
      ],
      if (others.isEmpty)
        HeritageCard(
          child: Text(
            _kind == BoardKind.friends
                ? l10n.socialFriendsEmpty
                : l10n.socialGlobalEmpty,
          ),
        )
      else
        for (var index = 0; index < board.entries.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: KunimSpacing.sm),
            child: _BoardRow(
              rank: index + 1,
              entry: board.entries[index],
              canRemove: _kind == BoardKind.friends,
            ),
          ),
      const SizedBox(height: KunimSpacing.lg),
      if (_kind == BoardKind.friends)
        FilledButton.icon(
          onPressed: () => showAddFriendSheet(context),
          icon: const Icon(Icons.person_add_alt_rounded),
          label: Text(l10n.socialAddFriend),
        ),
    ];
  }
}

/// How far the next person up is, or that nobody is. Null on a board with
/// only one name on it, where a gap would be meaningless.
String? _gapLine(AppLocalizations l10n, Board board) {
  final rank = board.myRank;
  if (rank == null || board.entries.length < 2) return null;
  if (rank == 1) return l10n.socialLeading;
  final me = board.entries[rank - 1];
  final ahead = board.entries[rank - 2];
  return l10n.socialGapAhead(
    ahead.name ?? l10n.socialNoName,
    ahead.pointsWeek - me.pointsWeek,
  );
}

class _SignInPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KunimSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.socialSignedOut, textAlign: TextAlign.center),
            const SizedBox(height: KunimSpacing.lg),
            FilledButton(
              onPressed: () => context.go(KunimRoutes.settingsAccount),
              child: Text(l10n.authSignInButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardRow extends ConsumerWidget {
  const _BoardRow({
    required this.rank,
    required this.entry,
    required this.canRemove,
  });

  final int rank;
  final BoardEntry entry;
  final bool canRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return HeritageCard(
      padding: const EdgeInsets.symmetric(
        horizontal: KunimSpacing.md,
        vertical: KunimSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text('$rank', style: theme.textTheme.titleMedium),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name ?? l10n.socialNoName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: entry.isMe ? theme.colorScheme.primary : null,
                  ),
                ),
                Text(
                  l10n.socialPointsTotal(entry.pointsTotal),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: KunimSpacing.sm),
          Text(
            l10n.statsPointsWeek(entry.pointsWeek),
            style: theme.textTheme.bodyMedium,
          ),
          if (canRemove && !entry.isMe)
            IconButton(
              tooltip: l10n.socialRemoveFriend,
              icon: const Icon(Icons.person_remove_outlined),
              onPressed: () => _confirmRemove(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.socialRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.logCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.socialRemoveFriend),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref
          .read(socialControllerProvider.notifier)
          .removeFriend(entry.userId);
    }
  }
}

/// Joining the global board: pick the name it lists you under.
class _JoinGlobalCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_JoinGlobalCard> createState() => _JoinGlobalCardState();
}

class _JoinGlobalCardState extends ConsumerState<_JoinGlobalCard> {
  final TextEditingController _nickname = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nickname.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return HeritageCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.socialJoinTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: KunimSpacing.xs),
          Text(
            l10n.socialJoinBody,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: KunimSpacing.md),
          TextField(
            controller: _nickname,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: l10n.socialNicknameLabel,
              hintText: l10n.socialNicknameHint,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: KunimSpacing.sm),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: KunimSpacing.md),
          FilledButton(
            onPressed: _busy || _nickname.text.trim().isEmpty ? null : _join,
            child: Text(l10n.socialJoin),
          ),
        ],
      ),
    );
  }

  Future<void> _join() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(socialControllerProvider.notifier).updateBoardProfile(
            nickname: _nickname.text,
            leaderboardOptIn: true,
          );
    } on SocialApiException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = socialErrorMessage(l10n, error.kind);
        });
      }
      return;
    }
    if (mounted) setState(() => _busy = false);
  }
}

/// Share your own code, or redeem a friend's.
Future<void> showAddFriendSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AddFriendSheet(),
  );
}

class _AddFriendSheet extends ConsumerStatefulWidget {
  const _AddFriendSheet();

  @override
  ConsumerState<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends ConsumerState<_AddFriendSheet> {
  final TextEditingController _code = TextEditingController();
  InviteCode? _mine;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mine = _mine;

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
            Text(l10n.socialAddFriend, style: theme.textTheme.titleLarge),
            const SizedBox(height: KunimSpacing.lg),
            Text(l10n.socialMyCode, style: theme.textTheme.titleSmall),
            const SizedBox(height: KunimSpacing.sm),
            if (mine == null)
              OutlinedButton.icon(
                onPressed: _busy ? null : _createCode,
                icon: const Icon(Icons.qr_code_rounded),
                label: Text(l10n.socialGetCode),
              )
            else
              InkWell(
                onTap: () => _copy(mine.code),
                child: HeritageCard(
                  child: Column(
                    children: [
                      Text(
                        mine.code,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: KunimSpacing.xs),
                      Text(
                        l10n.socialCodeExpires(
                          MaterialLocalizations.of(context)
                              .formatMediumDate(mine.expiresAt),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: KunimSpacing.xl),
            Text(l10n.socialEnterCode, style: theme.textTheme.titleSmall),
            const SizedBox(height: KunimSpacing.sm),
            TextField(
              controller: _code,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            if (_error != null) ...[
              const SizedBox(height: KunimSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: KunimSpacing.md),
            FilledButton(
              onPressed: _busy || _code.text.trim().isEmpty ? null : _accept,
              child: Text(l10n.socialSendCode),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code =
          await ref.read(socialControllerProvider.notifier).createInvite();
      if (mounted) setState(() => _mine = code);
    } on SocialApiException catch (error) {
      if (mounted) {
        setState(() => _error = socialErrorMessage(
              AppLocalizations.of(context),
              error.kind,
            ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String code) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: code));
    messenger.showSnackBar(SnackBar(content: Text(l10n.socialCodeCopied)));
  }

  Future<void> _accept() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(socialControllerProvider.notifier)
          .acceptInvite(_code.text);
    } on SocialApiException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = socialErrorMessage(l10n, error.kind);
        });
      }
      return;
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(l10n.socialFriendAdded)));
  }
}

String socialErrorMessage(AppLocalizations l10n, SocialErrorKind kind) {
  return switch (kind) {
    SocialErrorKind.codeNotFound => l10n.socialErrorCodeNotFound,
    SocialErrorKind.codeSpent => l10n.socialErrorCodeSpent,
    SocialErrorKind.ownCode => l10n.socialErrorOwnCode,
    SocialErrorKind.nicknameTaken => l10n.socialErrorNicknameTaken,
    SocialErrorKind.nicknameRequired => l10n.socialNicknameHint,
    SocialErrorKind.network => l10n.authErrorNetwork,
    SocialErrorKind.server => l10n.errorGeneric,
  };
}
