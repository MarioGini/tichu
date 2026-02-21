import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

class _FakeAgent extends PlayerAgent {
  @override
  final String playerId;

  _FakeAgent(this.playerId);

  @override
  Future<bool> shouldCallGrandTichu(final GameSnapshot snapshot) async => false;

  @override
  Future<bool> shouldCallTichu(final GameSnapshot snapshot) async => false;

  @override
  Future<SchupfAction> selectSchupfCards(final GameSnapshot snapshot) async {
    final hand = snapshot.hands[playerId]!;
    return SchupfAction(
      playerId: playerId,
      toLeft: hand[0],
      toPartner: hand[1],
      toRight: hand[2],
    );
  }

  @override
  Future<GameAction> selectTurn(final GameSnapshot snapshot) async =>
      PassAction(playerId: playerId);

  @override
  int selectDragonGive(final GameSnapshot snapshot) => 1;
}

void main() {
  test('PlayerAgent contract can be implemented and invoked', () async {
    final agent = _FakeAgent(aiTestSelfId);
    final snapshot = aiSnapshot(
      myHand: [
        Card(CardFace.two, CardColor.red),
        Card(CardFace.three, CardColor.blue),
        Card(CardFace.four, CardColor.green),
      ],
    );

    expect(await agent.shouldCallGrandTichu(snapshot), isFalse);
    expect(await agent.shouldCallTichu(snapshot), isFalse);
    expect(await agent.selectTurn(snapshot), isA<PassAction>());
    expect((await agent.selectSchupfCards(snapshot)).toLeft.face, CardFace.two);
    expect(agent.selectDragonGive(snapshot), 1);
  });
}
