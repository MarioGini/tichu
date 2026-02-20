import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/wish_logic.dart';

abstract class WishStrategy {
  CardFace selectWish(
    final GameSnapshot snapshot,
    final List<Card> hand,
    final DeckState deck, {
    final CardFace? preferredFace,
  });
}

class DefaultWishStrategy implements WishStrategy {
  const DefaultWishStrategy();

  @override
  CardFace selectWish(
    final GameSnapshot snapshot,
    final List<Card> hand,
    final DeckState deck, {
    final CardFace? preferredFace,
  }) {
    if (preferredFace != null && isWishableFace(preferredFace)) {
      return preferredFace;
    }

    const highCards = [
      CardFace.ace,
      CardFace.king,
      CardFace.queen,
      CardFace.jack,
      CardFace.ten,
    ];

    for (final face in highCards) {
      if (!hand.any((final c) => c.face == face)) {
        return face;
      }
    }

    return CardFace.none;
  }
}
