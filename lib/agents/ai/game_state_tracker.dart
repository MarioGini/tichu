import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';

class GameStateTracker {
  int _lastRoundNumber = 0;
  String? _lastPlayedBy;
  TichuTurn? _lastPlayedTurn;
  final Set<String> _seenCards = {};

  void reset() {
    _seenCards.clear();
    _lastPlayedBy = null;
    _lastPlayedTurn = null;
  }

  void update(GameSnapshot snapshot, String playerId) {
    if (_lastRoundNumber != snapshot.scoreState.roundNumber) {
      _lastRoundNumber = snapshot.scoreState.roundNumber;
      reset();
    }

    final hand = snapshot.hands[playerId] ?? const <Card>[];
    _addCards(hand);

    final receipts =
        snapshot.schupfReceipts[playerId] ?? const <SchupfReceipt>[];
    _addCards(receipts.map((r) => r.card));

    final lastTurn = snapshot.lastPlayedTurn;
    if (lastTurn != null &&
        (snapshot.lastPlayedBy != _lastPlayedBy ||
            lastTurn != _lastPlayedTurn)) {
      _lastPlayedBy = snapshot.lastPlayedBy;
      _lastPlayedTurn = lastTurn;
      _addCards(lastTurn.cards);
    }
  }

  bool get allAcesKnown => _knownCount(CardFace.ace) >= 4;

  bool get allKingsKnown => _knownCount(CardFace.king) >= 4;

  bool hasLastAce(List<Card> hand) {
    return allAcesKnown && hand.any((c) => c.face == CardFace.ace);
  }

  bool hasLastKing(List<Card> hand) {
    return allKingsKnown && hand.any((c) => c.face == CardFace.king);
  }

  int _knownCount(CardFace face) {
    return _seenCards.where((key) => key.startsWith('${face.name}:')).length;
  }

  void _addCards(Iterable<Card> cards) {
    for (final card in cards) {
      _seenCards.add('${card.face.name}:${card.color.name}');
    }
  }
}
