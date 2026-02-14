import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/driver_ui_projector.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import '../utils/test_game_fixtures.dart';

void main() {
  const projector = DriverUiProjector();

  test('manual mode preserves manual selected indexes', () {
    final snapshot = buildPlayerSnapshot(
      phase: GamePhase.play,
      currentPlayerId: testHumanId,
      hand: [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.ace, CardColor.green),
      ],
    );

    final projection = projector.project(
      snapshot: snapshot,
      humanId: testHumanId,
      isSelfManual: true,
      hand: snapshot.hand,
      currentSelectedIndexes: {1},
      currentSchupfToLeft: null,
      currentSchupfToPartner: null,
      currentSchupfToRight: null,
    );

    expect(projection.selectedIndexes, {1});
  });

  test('ai mode mirrors pending self play cards to selected indexes', () {
    final ace = Card(CardFace.ace, CardColor.green);
    final snapshot = buildPlayerSnapshot(
      phase: GamePhase.play,
      currentPlayerId: testHumanId,
      hand: [Card(CardFace.two, CardColor.red), ace],
      pendingOpponentPlayerId: testHumanId,
      pendingOpponentCards: [ace],
      opponentAwaitingConfirmation: true,
    );

    final projection = projector.project(
      snapshot: snapshot,
      humanId: testHumanId,
      isSelfManual: false,
      hand: snapshot.hand,
      currentSelectedIndexes: const <int>{},
      currentSchupfToLeft: null,
      currentSchupfToPartner: null,
      currentSchupfToRight: null,
    );

    expect(projection.selectedIndexes, hasLength(1));
    expect(snapshot.hand.elementAt(projection.selectedIndexes.first), ace);
  });

  test('ai schupf maps pending self cards into schupf slots', () {
    final toLeft = Card(CardFace.ace, CardColor.green);
    final toPartner = Card(CardFace.king, CardColor.red);
    final toRight = Card(CardFace.queen, CardColor.blue);
    final snapshot = buildPlayerSnapshot(
      phase: GamePhase.schupf,
      currentPlayerId: testHumanId,
      hand: [toLeft, toPartner, toRight],
      schupfCompletedPlayers: const <String>[],
      pendingOpponentPlayerId: testHumanId,
      pendingOpponentCards: [toLeft, toPartner, toRight],
    );

    final projection = projector.project(
      snapshot: snapshot,
      humanId: testHumanId,
      isSelfManual: false,
      hand: snapshot.hand,
      currentSelectedIndexes: const <int>{},
      currentSchupfToLeft: null,
      currentSchupfToPartner: null,
      currentSchupfToRight: null,
    );

    expect(projection.schupfToLeft, toLeft);
    expect(projection.schupfToPartner, toPartner);
    expect(projection.schupfToRight, toRight);
    expect(projection.pendingOpponentCards, isEmpty);
  });
}
