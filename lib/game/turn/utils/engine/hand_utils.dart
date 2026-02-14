import 'package:tichu/game/turn/tichu_data.dart';

bool handContainsAll(List<Card> hand, List<Card> cards) {
  final temp = List<Card>.from(hand);
  for (final card in cards) {
    final index = temp.indexWhere((candidate) {
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

void removeCardsFromHand(List<Card> hand, List<Card> cards) {
  for (final card in cards) {
    final index = hand.indexWhere((candidate) {
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

(Card toLeft, Card toPartner, Card toRight) fallbackSchupf(List<Card> hand) {
  if (hand.length < 3) {
    throw StateError('Not enough cards to schupf.');
  }
  final sorted = List<Card>.from(hand)
    ..sort((a, b) => a.value.compareTo(b.value));
  return (sorted[0], sorted[1], sorted[2]);
}
