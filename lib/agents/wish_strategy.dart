import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';

abstract class WishStrategy {
  CardFace selectWish(
    GameSnapshot snapshot,
    List<Card> hand,
    DeckState deck, {
    CardFace? preferredFace,
  });
}

class DefaultWishStrategy implements WishStrategy {
  const DefaultWishStrategy();

  @override
  CardFace selectWish(
    GameSnapshot snapshot,
    List<Card> hand,
    DeckState deck, {
    CardFace? preferredFace,
  }) {
    if (preferredFace != null && _isWishableFace(preferredFace)) {
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
      if (!hand.any((c) => c.face == face)) {
        return face;
      }
    }

    return CardFace.none;
  }

  bool _isWishableFace(CardFace face) {
    switch (face) {
      case CardFace.two:
      case CardFace.three:
      case CardFace.four:
      case CardFace.five:
      case CardFace.six:
      case CardFace.seven:
      case CardFace.eight:
      case CardFace.nine:
      case CardFace.ten:
      case CardFace.jack:
      case CardFace.queen:
      case CardFace.king:
      case CardFace.ace:
        return true;
      default:
        return false;
    }
  }
}
