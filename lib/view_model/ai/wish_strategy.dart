import 'package:tichu/services/game_backend.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';

abstract class WishStrategy {
  CardFace selectWish(GameSnapshot snapshot, List<Card> hand, DeckState deck);
}

class DefaultWishStrategy implements WishStrategy {
  const DefaultWishStrategy();

  @override
  CardFace selectWish(GameSnapshot snapshot, List<Card> hand, DeckState deck) {
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
}
