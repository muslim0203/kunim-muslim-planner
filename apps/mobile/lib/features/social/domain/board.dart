/// What the server returns for a board, and for a fresh invite code.
///
/// A board row carries an id, the name its owner chose to show and their
/// points — never an email. [BoardEntry.name] is null when the person has
/// picked neither a nickname nor a display name; the screen shows its own
/// placeholder rather than the server inventing one.
library;

class BoardEntry {
  const BoardEntry({
    required this.userId,
    required this.name,
    required this.pointsWeek,
    required this.pointsTotal,
    required this.isMe,
  });

  factory BoardEntry.fromJson(Map<String, dynamic> json) {
    return BoardEntry(
      userId: json['user_id'] as String,
      name: json['name'] as String?,
      pointsWeek: (json['points_week'] as num).toInt(),
      pointsTotal: (json['points_total'] as num).toInt(),
      isMe: json['is_me'] as bool? ?? false,
    );
  }

  final String userId;
  final String? name;
  final int pointsWeek;
  final int pointsTotal;
  final bool isMe;
}

class Board {
  const Board({required this.entries, required this.myRank});

  factory Board.fromJson(Map<String, dynamic> json) {
    return Board(
      entries: [
        for (final entry in (json['entries'] as List<dynamic>? ?? const []))
          BoardEntry.fromJson((entry as Map).cast<String, dynamic>()),
      ],
      myRank: (json['my_rank'] as num?)?.toInt(),
    );
  }

  /// Best week first.
  final List<BoardEntry> entries;

  /// The signed-in user's position, or `null` when they are not on the board.
  final int? myRank;

  bool get isEmpty => entries.isEmpty;
}

class InviteCode {
  const InviteCode({required this.code, required this.expiresAt});

  factory InviteCode.fromJson(Map<String, dynamic> json) {
    return InviteCode(
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    );
  }

  final String code;
  final DateTime expiresAt;
}
