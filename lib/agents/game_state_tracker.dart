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

  void update(final GameSnapshot snapshot, final String playerId) {
    if (_lastRoundNumber != snapshot.scoreState.roundNumber) {
      _lastRoundNumber = snapshot.scoreState.roundNumber;
      reset();
    }

    final hand = snapshot.hands[playerId] ?? const <Card>[];
    _addCards(hand);

    final receipts =
        snapshot.schupfReceipts[playerId] ?? const <SchupfReceipt>[];
    _addCards(receipts.map((final r) => r.card));

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

  bool hasLastAce(final List<Card> hand) => allAcesKnown && hand.any((final c) => c.face == CardFace.ace);

  bool hasLastKing(final List<Card> hand) => allKingsKnown && hand.any((final c) => c.face == CardFace.king);

  int _knownCount(final CardFace face) => _seenCards.where((final key) => key.startsWith('${face.name}:')).length;

  void _addCards(final Iterable<Card> cards) {
    for (final card in cards) {
      _seenCards.add('${card.face.name}:${card.color.name}');
    }
  }
}
