import '../turn/tichu_data.dart';

class SchupfSelection {
  Card fromLeft;
  Card fromPartner;
  Card fromRight;
}

class SchupfSend {
  Card toLeft;
  Card toPartner;
  Card toRight;
}

class Schupfer {
  Map<String, SchupfSelection> receivedCards;

  SchupfSelection receiveCards(String id) {
    return receivedCards[id];
  }

  void processSchupf(SchupfSend input) {}
}
