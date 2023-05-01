import 'package:tichu/view_model/turn/tichu_data.dart';

class StoreAPI {
  final String tableUid;
  final String playerUid;

  //DocumentReference cardDoc; // Reference to cards of the
  //DocumentReference deckRef;

  StoreAPI()
      : tableUid = '1',
        playerUid = '1';
  //   {cardDoc = instance
  //       .collection('table')
  //       .document(tableUid)
  //       .collection('cards')
  //       .document(playerUid);
  //   deckRef = instance
  //       .collection('tables')
  //       .document(tableUid)
  //       .collection('deck')
  //       .document('current');
  // }

  // Future<List<Card>> getCards() async {
  //   //final doc = await cardDoc.get();

  //   var cards = <int>[];
  //   // cards = doc['cards'].cast<int>();

  //   return cards.map((e) => cardIdentifiers[e]).toList();
  // }

  // Map<String, Card> getSchupfCards() {
  //   // We wait as long until the stream contains a map with three elements.
  //   return {};
  // }

  void sendSchupfCards(Map<String, Card> schupfCards) {
    // move into the correct path
  }

  Stream<DeckState> deckStateStream() {
    //var bla = deckRef.snapshots();
    var bla;
    var deckStream = bla.map(
        (docSnap) => DeckState(docSnap.data['turn'], docSnap.data['wish']));

    return deckStream;
  }

  void updateDeckState(DeckState deckState) {
    // Deck will also handle the scoring, we just put the cards into a separate
    // field.
    // Send updated to fire store
    //deckRef.updateData(null);
  }

  static final Map<int, Card> cardIdentifiers = {
    0: Card(CardFace.ace, Color.green),
    1: Card(CardFace.two, Color.green),
    2: Card(CardFace.three, Color.green),
    3: Card(CardFace.four, Color.green),
    4: Card(CardFace.five, Color.green),
    5: Card(CardFace.six, Color.green),
    6: Card(CardFace.seven, Color.green),
    7: Card(CardFace.eight, Color.green),
    8: Card(CardFace.nine, Color.green),
    9: Card(CardFace.ten, Color.green),
    10: Card(CardFace.jack, Color.green),
    11: Card(CardFace.queen, Color.green),
    12: Card(CardFace.king, Color.green),
    13: Card(CardFace.ace, Color.blue),
    14: Card(CardFace.two, Color.blue),
    15: Card(CardFace.three, Color.blue),
    16: Card(CardFace.four, Color.blue),
    17: Card(CardFace.five, Color.blue),
    18: Card(CardFace.six, Color.blue),
    19: Card(CardFace.seven, Color.blue),
    20: Card(CardFace.eight, Color.blue),
    21: Card(CardFace.nine, Color.blue),
    22: Card(CardFace.ten, Color.blue),
    23: Card(CardFace.jack, Color.blue),
    24: Card(CardFace.queen, Color.blue),
    25: Card(CardFace.king, Color.blue),
    26: Card(CardFace.ace, Color.black),
    27: Card(CardFace.two, Color.black),
    28: Card(CardFace.three, Color.black),
    29: Card(CardFace.four, Color.black),
    30: Card(CardFace.five, Color.black),
    31: Card(CardFace.six, Color.black),
    32: Card(CardFace.seven, Color.black),
    33: Card(CardFace.eight, Color.black),
    34: Card(CardFace.nine, Color.black),
    35: Card(CardFace.ten, Color.black),
    36: Card(CardFace.jack, Color.black),
    37: Card(CardFace.queen, Color.black),
    38: Card(CardFace.king, Color.black),
    39: Card(CardFace.ace, Color.red),
    40: Card(CardFace.two, Color.red),
    41: Card(CardFace.three, Color.red),
    42: Card(CardFace.four, Color.red),
    43: Card(CardFace.five, Color.red),
    44: Card(CardFace.six, Color.red),
    45: Card(CardFace.seven, Color.red),
    46: Card(CardFace.eight, Color.red),
    47: Card(CardFace.nine, Color.red),
    48: Card(CardFace.ten, Color.red),
    49: Card(CardFace.jack, Color.red),
    50: Card(CardFace.queen, Color.red),
    51: Card(CardFace.king, Color.red),
    52: Card(CardFace.mahJong, Color.special),
    53: Card(CardFace.phoenix, Color.special),
    54: Card(CardFace.dog, Color.special),
    55: Card(CardFace.dragon, Color.special),
  };
}
