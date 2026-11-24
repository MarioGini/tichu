import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/scoreboard/scoreboard_model.dart';

void main() {
  group('ScoreboardRound', () {
    test('card points split to 100', () {
      const r = ScoreboardRound(cardPointsTeamA: 65);
      expect(r.totalFor(0), 65);
      expect(r.totalFor(1), 35);
    });

    test('phoenix extremes', () {
      const r = ScoreboardRound(cardPointsTeamA: -25);
      expect(r.totalFor(0), -25);
      expect(r.totalFor(1), 125);
      expect(r.isValid, isTrue);
    });

    test('double victory scores 200 and ignores card points', () {
      const r = ScoreboardRound(cardPointsTeamA: 80, doubleVictoryTeam: 1);
      expect(r.totalFor(0), 0);
      expect(r.totalFor(1), 200);
    });

    test('tichu calls add and subtract', () {
      const r = ScoreboardRound(
        cardPointsTeamA: 30,
        calls: [
          TichuCall(team: 0, kind: TichuCallKind.tichu, success: true),
          TichuCall(team: 1, kind: TichuCallKind.grandTichu, success: false),
        ],
      );
      expect(r.totalFor(0), 130);
      expect(r.totalFor(1), 70 - 200);
    });

    test('rejects two successful calls', () {
      const r = ScoreboardRound(
        calls: [
          TichuCall(team: 0, kind: TichuCallKind.tichu, success: true),
          TichuCall(team: 1, kind: TichuCallKind.tichu, success: true),
        ],
      );
      expect(r.isValid, isFalse);
    });

    test('rejects successful call against a double victory', () {
      const r = ScoreboardRound(
        doubleVictoryTeam: 0,
        calls: [TichuCall(team: 1, kind: TichuCallKind.tichu, success: true)],
      );
      expect(r.isValid, isFalse);
    });

    test('rejects card points off the 5 grid or out of range', () {
      expect(const ScoreboardRound(cardPointsTeamA: 52).isValid, isFalse);
      expect(const ScoreboardRound(cardPointsTeamA: 130).isValid, isFalse);
    });

    test('rejects three calls for a team', () {
      const call = TichuCall(
        team: 0,
        kind: TichuCallKind.tichu,
        success: false,
      );
      expect(const ScoreboardRound(calls: [call, call, call]).isValid, isFalse);
    });
  });

  group('ScoreboardGame', () {
    ScoreboardGame game(List<ScoreboardRound> rounds) => ScoreboardGame.start(
      teamNames: const ['A', 'B'],
      now: DateTime(2026),
    ).copyWith(rounds: rounds);

    test('running totals and winner', () {
      final g = game(const [
        ScoreboardRound(doubleVictoryTeam: 0),
        ScoreboardRound(
          cardPointsTeamA: 70,
          calls: [
            TichuCall(team: 0, kind: TichuCallKind.grandTichu, success: true),
          ],
        ),
      ]);
      expect(g.runningTotals, [
        [200, 0],
        [470, 30],
      ]);
      expect(g.winner, isNull);
      final done = g.copyWith(targetScore: 400);
      expect(done.winner, 0);
    });

    test('tie above target keeps playing', () {
      final g = game(const [ScoreboardRound()]).copyWith(targetScore: 50);
      expect(g.totalFor(0), 50);
      expect(g.totalFor(1), 50);
      expect(g.winner, isNull);
    });

    test('json round trip', () {
      final g = game(const [
        ScoreboardRound(
          cardPointsTeamA: 15,
          calls: [TichuCall(team: 1, kind: TichuCallKind.tichu, success: true)],
        ),
        ScoreboardRound(doubleVictoryTeam: 1),
      ]);
      final back = ScoreboardGame.fromJson(g.toJson());
      expect(back.toJson(), g.toJson());
      expect(back.totalFor(1), g.totalFor(1));
    });

    test('fromJson rejects malformed teams', () {
      final json = game(const []).toJson();
      final oneTeam = Map<String, Object?>.of(json)..['teamNames'] = ['A'];
      expect(() => ScoreboardGame.fromJson(oneTeam), throwsFormatException);
      final badTeam = Map<String, Object?>.of(json)
        ..['rounds'] = [
          const ScoreboardRound().toJson()..['doubleVictoryTeam'] = 2,
        ];
      expect(() => ScoreboardGame.fromJson(badTeam), throwsFormatException);
    });
  });
}
