import '../services/firestore_api.dart';
import 'turn/tichu_data.dart';
import 'turn/turn_handler.dart';

class Player {
  final Player left;
  final Player partner;
  final Player right;
  final StoreAPI storeAPI;

  List<Card> handCards;
  bool grandTichu;
  bool tichu;
  int numCards;

  int finishNumber;

  List<Card> madeCards;

  TurnHandler turnHandler;

  Player(this.left, this.partner, this.right, this.storeAPI);

  Future<void> preGame() async {
    handCards = await storeAPI.getCards();

    // First show eight cards, then await grand tichu decision.

    // Show all cards, switch to schupfen dialogue.
    var schupfCards = obtainSchupfedCards();
    storeAPI.sendSchupfCards(schupfCards);

    // Await readiness. Check whether we have the mahjong, in which case we can
    // begin.
  }

  Future<void> gameTurn(List<Card> cards) async {
    var deck = await storeAPI.deckStateStream().last;

    // When phoenix is contained, switch to phoenix handler screen
    if (cards.any((element) => element.face == CardFace.phoenix)) {
      var phoenix = phoenixDialogue(deck);
      cards.removeWhere((element) => element.face == CardFace.phoenix);
      cards.add(phoenix);
    }

    // Check whether the wish card is contained
    CardFace inputWish;
    if (cards.any((element) => element.face == CardFace.mahJong)) {
      // Check for valid turn.
      inputWish = obtainWishValue();
    }

    var updatedDeck = turnHandler.handleTurn(deck, cards, inputWish);

    // Also immediately display the deck state.
    storeAPI.updateDeckState(updatedDeck);
  }
}

Card phoenixDialogue(DeckState currentDeck) {
  Card phoenix;

  if (currentDeck.turn.type == TurnType.single ||
      currentDeck.turn.type == TurnType.empty) {
    phoenix = Card.phoenix(currentDeck.turn.value + 0.5);
  } else {
    phoenix = Card.phoenix(obtainPhoenixValue());
  }

  return phoenix;
}

// User side facing code below
double obtainPhoenixValue() {
  // This value needs to be obtained from user input.
  return 2.0;
}

CardFace obtainWishValue() {
  // This value needs to be obtained from user input.
  return CardFace.nine;
}

bool obtainGrandTichu() {
  return false;
}

bool obtainTichu() {
  return false;
}

Map<String, Card> obtainSchupfedCards() {
  return {};
}
