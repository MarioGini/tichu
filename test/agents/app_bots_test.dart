import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/agents/app_bots.dart';
import 'package:tichu/agents/app_bots_loader.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/turn/tichu_data.dart';

import 'ai_test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the bundled play policy and makes legal moves', () async {
    await loadAppBotsFromAssets();
    expect(AppBots.current.play, isNotNull);

    final hand = [
      Card(CardFace.two, CardColor.red),
      Card(CardFace.five, CardColor.blue),
      Card(CardFace.king, CardColor.green),
    ];
    final agent = AppBots.current.build(aiTestSelfId);
    final action = await agent.selectTurn(aiSnapshot(myHand: hand));
    expect(action, isA<PlayTurnAction>());
    final played = (action as PlayTurnAction).cards.single;
    expect(hand.any((final c) => c.face == played.face), isTrue);
  });
}
