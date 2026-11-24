import 'package:meta/meta.dart';

/// Scorekeeping for Tichu played at a real table: the players count their
/// cards and the app adds up rounds, Tichu calls and double victories.

int _team(int team) {
  if (team != 0 && team != 1) {
    throw FormatException('team must be 0 or 1, got $team');
  }
  return team;
}

List<String> _teamNames(List<Object?> names) {
  if (names.length != 2) {
    throw FormatException('expected 2 team names, got ${names.length}');
  }
  return [for (final n in names) n! as String];
}

enum TichuCallKind {
  tichu(100),
  grandTichu(200);

  const TichuCallKind(this.value);

  /// Points won when the call succeeds, lost when it fails.
  final int value;

  String get label => switch (this) {
    TichuCallKind.tichu => 'Tichu',
    TichuCallKind.grandTichu => 'Grand Tichu',
  };
}

/// One player's Tichu or Grand Tichu call in a round.
@immutable
class TichuCall {
  const TichuCall({
    required this.team,
    required this.kind,
    required this.success,
  });

  factory TichuCall.fromJson(Map<String, Object?> json) => TichuCall(
    team: _team(json['team']! as int),
    kind: TichuCallKind.values.byName(json['kind']! as String),
    success: json['success']! as bool,
  );

  /// 0 or 1.
  final int team;
  final TichuCallKind kind;

  /// The caller went out first.
  final bool success;

  int get points => success ? kind.value : -kind.value;

  TichuCall copyWith({TichuCallKind? kind, bool? success}) => TichuCall(
    team: team,
    kind: kind ?? this.kind,
    success: success ?? this.success,
  );

  Map<String, Object?> toJson() => {
    'team': team,
    'kind': kind.name,
    'success': success,
  };

  @override
  bool operator ==(Object other) =>
      other is TichuCall &&
      other.team == team &&
      other.kind == kind &&
      other.success == success;

  @override
  int get hashCode => Object.hash(team, kind, success);
}

/// One played round as entered at the table.
@immutable
class ScoreboardRound {
  const ScoreboardRound({
    this.cardPointsTeamA = 50,
    this.doubleVictoryTeam,
    this.calls = const <TichuCall>[],
  });

  factory ScoreboardRound.fromJson(Map<String, Object?> json) =>
      ScoreboardRound(
        cardPointsTeamA: json['cardPointsTeamA']! as int,
        doubleVictoryTeam: switch (json['doubleVictoryTeam'] as int?) {
          null => null,
          final t => _team(t),
        },
        calls: [
          for (final c in json['calls']! as List<Object?>)
            TichuCall.fromJson(Map<String, Object?>.from(c! as Map)),
        ],
      );

  static const int minCardPoints = -25;
  static const int maxCardPoints = 125;

  /// Card points counted by team A (team B has `100 - cardPointsTeamA`).
  /// Ignored when [doubleVictoryTeam] is set.
  final int cardPointsTeamA;

  /// The team that made a match (double victory): its two players went
  /// out first and second.
  final int? doubleVictoryTeam;

  final List<TichuCall> calls;

  /// Card points (or the 200 of a match) for [team].
  int cardPointsFor(int team) {
    final dv = doubleVictoryTeam;
    if (dv != null) return dv == team ? 200 : 0;
    return team == 0 ? cardPointsTeamA : 100 - cardPointsTeamA;
  }

  /// Tichu / Grand Tichu bonuses and penalties for [team].
  int callPointsFor(int team) {
    var total = 0;
    for (final call in calls) {
      if (call.team == team) total += call.points;
    }
    return total;
  }

  int totalFor(int team) => cardPointsFor(team) + callPointsFor(team);

  /// Rule violations; empty when the round can be saved.
  List<String> validate() {
    final errors = <String>[];
    final dv = doubleVictoryTeam;
    if (dv == null &&
        (cardPointsTeamA < minCardPoints ||
            cardPointsTeamA > maxCardPoints ||
            cardPointsTeamA % 5 != 0)) {
      errors.add('Card points must be a multiple of 5 from -25 to 125.');
    }
    for (final team in const [0, 1]) {
      if (calls.where((c) => c.team == team).length > 2) {
        errors.add('A team has only two players to call Tichu.');
      }
    }
    final made = calls.where((c) => c.success).toList();
    if (made.length > 1) {
      errors.add('Only one player can go out first.');
    }
    if (dv != null && made.any((c) => c.team != dv)) {
      errors.add(
        'A call against a match cannot succeed: '
        'the other team went out first.',
      );
    }
    return errors;
  }

  bool get isValid => validate().isEmpty;

  ScoreboardRound copyWith({
    int? cardPointsTeamA,
    int? Function()? doubleVictoryTeam,
    List<TichuCall>? calls,
  }) => ScoreboardRound(
    cardPointsTeamA: cardPointsTeamA ?? this.cardPointsTeamA,
    doubleVictoryTeam: doubleVictoryTeam != null
        ? doubleVictoryTeam()
        : this.doubleVictoryTeam,
    calls: calls ?? this.calls,
  );

  Map<String, Object?> toJson() => {
    'cardPointsTeamA': cardPointsTeamA,
    'doubleVictoryTeam': doubleVictoryTeam,
    'calls': [for (final c in calls) c.toJson()],
  };
}

/// A match played at a real table, round by round.
@immutable
class ScoreboardGame {
  const ScoreboardGame({
    required this.id,
    required this.teamNames,
    this.targetScore = 1000,
    this.rounds = const <ScoreboardRound>[],
    required this.startedAt,
  });

  factory ScoreboardGame.start({
    required List<String> teamNames,
    int targetScore = 1000,
    DateTime? now,
  }) {
    final started = now ?? DateTime.now();
    return ScoreboardGame(
      id: 'sb-${started.millisecondsSinceEpoch}',
      teamNames: teamNames,
      targetScore: targetScore,
      startedAt: started,
    );
  }

  factory ScoreboardGame.fromJson(Map<String, Object?> json) => ScoreboardGame(
    id: json['id']! as String,
    teamNames: _teamNames(json['teamNames']! as List<Object?>),
    targetScore: json['targetScore']! as int,
    startedAt: DateTime.parse(json['startedAt']! as String),
    rounds: [
      for (final r in json['rounds']! as List<Object?>)
        ScoreboardRound.fromJson(Map<String, Object?>.from(r! as Map)),
    ],
  );

  final String id;

  /// Exactly two names, team A first.
  final List<String> teamNames;
  final int targetScore;
  final List<ScoreboardRound> rounds;
  final DateTime startedAt;

  int totalFor(int team) {
    var total = 0;
    for (final r in rounds) {
      total += r.totalFor(team);
    }
    return total;
  }

  /// Running totals after each round, `[teamA, teamB]` per round.
  List<List<int>> get runningTotals {
    var a = 0;
    var b = 0;
    return [
      for (final r in rounds) [a += r.totalFor(0), b += r.totalFor(1)],
    ];
  }

  /// The winning team once a team has reached the target with more points
  /// than the other; a tie at or above the target keeps the match going.
  int? get winner {
    final a = totalFor(0);
    final b = totalFor(1);
    if (a < targetScore && b < targetScore) return null;
    if (a == b) return null;
    return a > b ? 0 : 1;
  }

  bool get isFinished => winner != null;

  ScoreboardGame copyWith({
    List<String>? teamNames,
    int? targetScore,
    List<ScoreboardRound>? rounds,
  }) => ScoreboardGame(
    id: id,
    teamNames: teamNames ?? this.teamNames,
    targetScore: targetScore ?? this.targetScore,
    rounds: rounds ?? this.rounds,
    startedAt: startedAt,
  );

  ScoreboardGame addRound(ScoreboardRound round) =>
      copyWith(rounds: [...rounds, round]);

  ScoreboardGame replaceRound(int index, ScoreboardRound round) =>
      copyWith(rounds: [...rounds]..[index] = round);

  ScoreboardGame removeRound(int index) =>
      copyWith(rounds: [...rounds]..removeAt(index));

  Map<String, Object?> toJson() => {
    'id': id,
    'teamNames': teamNames,
    'targetScore': targetScore,
    'startedAt': startedAt.toIso8601String(),
    'rounds': [for (final r in rounds) r.toJson()],
  };
}
