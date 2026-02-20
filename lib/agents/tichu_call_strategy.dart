import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';
import 'package:tichu/game/turn/utils/card_utils.dart';
import 'package:tichu/game/turn/utils/straight_utils.dart';

abstract class TichuCallStrategy {
  Future<bool> shouldCallGrandTichu(GameSnapshot snapshot, String playerId);
  Future<bool> shouldCallTichu(GameSnapshot snapshot, String playerId);
}

class DefaultTichuCallStrategy implements TichuCallStrategy {
  static const int _tichuIndexThreshold = 7;

  const DefaultTichuCallStrategy();

  @override
  Future<bool> shouldCallGrandTichu(
    GameSnapshot snapshot,
    String playerId,
  ) async {
    return false;
  }

  @override
  Future<bool> shouldCallTichu(GameSnapshot snapshot, String playerId) async {
    final hand = snapshot.hands[playerId] ?? const <Card>[];
    return _tichuIndex(hand) >= _tichuIndexThreshold;
  }

  int _tichuIndex(List<Card> hand) {
    final nAce = _countFace(hand, CardFace.ace);
    final nDog = _countFace(hand, CardFace.dog);
    final nDragon = _countFace(hand, CardFace.dragon);
    final nPhoenix = _countFace(hand, CardFace.phoenix);
    final nBomb = getBombs(List<Card>.from(hand)).length;
    final nStraight = getStraights(List<Card>.from(hand), 5).length;
    final nSmallSingleton = _smallSingletonCount(hand);

    return 2 * nAce -
        2 * nDog +
        6 * nDragon +
        6 * nPhoenix +
        5 * nBomb +
        nStraight -
        nSmallSingleton;
  }

  int _smallSingletonCount(List<Card> hand) {
    final normalCards = hand
        .where(
          (c) =>
              c.face != CardFace.dragon &&
              c.face != CardFace.phoenix &&
              c.face != CardFace.dog,
        )
        .toList();
    final occurrence = getOccurrenceCount(normalCards);
    var count = 0;
    for (final entry in occurrence.entries) {
      if (entry.value != 1) {
        continue;
      }
      final value = Card.getValue(entry.key);
      if (value >= 2 && value <= 7) {
        count += 1;
      }
    }
    return count;
  }

  int _countFace(List<Card> hand, CardFace face) {
    return hand.where((card) => card.face == face).length;
  }
}
