import 'package:tichu/game/turn/tichu_data.dart';

bool handContainsAll(final List<Card> hand, final List<Card> cards) {
  final temp = List<Card>.from(hand);
  for (final card in cards) {
    final index = temp.indexWhere((final candidate) {
      if (card.face == CardFace.phoenix) {
        return candidate.face == CardFace.phoenix;
      }
      return candidate.face == card.face && candidate.color == card.color;
    });
    if (index == -1) {
      return false;
    }
    temp.removeAt(index);
  }
  return true;
}

void removeCardsFromHand(final List<Card> hand, final List<Card> cards) {
  for (final card in cards) {
    final index = hand.indexWhere((final candidate) {
      if (card.face == CardFace.phoenix) {
        return candidate.face == CardFace.phoenix;
      }
      return candidate.face == card.face && candidate.color == card.color;
    });
    if (index != -1) {
      hand.removeAt(index);
    }
  }
}

(Card toLeft, Card toPartner, Card toRight) fallbackSchupf(
  final List<Card> hand,
) {
  if (hand.length < 3) {
    throw StateError('Not enough cards to schupf.');
  }
  final sorted = List<Card>.from(hand)
    ..sort((final a, final b) => a.value.compareTo(b.value));
  return (sorted[0], sorted[1], sorted[2]);
}
