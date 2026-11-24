import 'package:tichu/game/turn/tichu_data.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DeckState emptyDeck() =>
    DeckState(TichuTurn(TurnType.empty, const []), CardFace.none);

DeckState singleDeck(CardFace face) {
  final deck = DeckState(
    TichuTurn(TurnType.single, [Card(face, CardColor.red)]),
    CardFace.none,
  );
  deck.currentWinner = 'other';
  return deck;
}

DeckState pairDeck(CardFace face) {
  final deck = DeckState(
    TichuTurn(TurnType.pair, [
      Card(face, CardColor.red),
      Card(face, CardColor.blue),
    ]),
    CardFace.none,
  );
  deck.currentWinner = 'other';
  return deck;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
