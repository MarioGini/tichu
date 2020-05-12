import 'package:cloud_firestore/cloud_firestore.dart';

import '../view_model/turn/tichu_data.dart';

class StoreAPI {
  final String tableUid;
  final String playerUid;
  final Firestore instance;

  DocumentReference cardDoc;

  StoreAPI(this.instance)
      : tableUid = '1',
        playerUid = '1' {
    cardDoc = instance
        .collection('table')
        .document(tableUid)
        .collection('cards')
        .document(playerUid);
  }

  List<int> readCards() {
    final doc = cardDoc.get();

    var cards = [];

    doc.then((value) => cards = value['cards'].cast<int>());

    return cards;
  }
}

Future<List<Card>> getCards(String uid) async {
  var store = StoreAPI(Firestore.instance);

  var list = await store.readCards();
  return list.map((e) => cardIdentifiers[e]).toList();
}

Map<int, Card> cardIdentifiers = {
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
