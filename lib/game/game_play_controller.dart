import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/wish_logic.dart';
import 'package:tichu/game/turn_rules_adapter.dart';

class GamePlayController {
  final TurnRulesAdapter _turnRules;

  GamePlayController({TurnRulesAdapter? turnRules})
    : _turnRules = turnRules ?? TurnRulesAdapter();

  TichuTurn? resolveSelectedTurn({
    required PlayerSnapshot snapshot,
    required List<Card> selectedCards,
    required List<Card> hand,
  }) {
    if (selectedCards.isEmpty) {
      return null;
    }

    final selectedTurn = _turnRules.detectTurn(selectedCards);
    if (selectedTurn == TichuTurn.invalid()) {
      return null;
    }

    final updated = _turnRules.tryApplyTurn(
      snapshot.deck,
      selectedCards,
      CardFace.none,
      hand: hand,
    );
    if (updated.turn == TichuTurn.invalid()) {
      return null;
    }

    return selectedTurn;
  }

  bool canPlaySelected({
    required PlayerSnapshot snapshot,
    required String humanId,
    required List<Card> hand,
    required List<Card> selectedCards,
    required bool schupfAckPending,
  }) {
    if (!_isPlayTurnForHuman(snapshot, humanId, schupfAckPending)) {
      return false;
    }
    if (selectedCards.isEmpty) {
      return false;
    }
    return resolveSelectedTurn(
          snapshot: snapshot,
          selectedCards: selectedCards,
          hand: hand,
        ) !=
        null;
  }

  bool canPlayAny({
    required PlayerSnapshot snapshot,
    required String humanId,
    required List<Card> hand,
    required bool schupfAckPending,
  }) {
    if (!_isPlayTurnForHuman(snapshot, humanId, schupfAckPending)) {
      return false;
    }

    final legalTurns = _turnRules.legalTurns(snapshot.deck, hand);
    for (final turn in legalTurns) {
      final updated = _turnRules.tryApplyTurn(
        snapshot.deck,
        turn.cards,
        CardFace.none,
        hand: hand,
      );
      if (updated.turn != TichuTurn.invalid()) {
        return true;
      }
    }

    return false;
  }

  bool canPass({
    required PlayerSnapshot snapshot,
    required String humanId,
    required List<Card> hand,
    required bool schupfAckPending,
  }) {
    if (!_isPlayTurnForHuman(snapshot, humanId, schupfAckPending)) {
      return false;
    }

    final deckType = snapshot.deck.turn.type;
    if (deckType == TurnType.empty || deckType == TurnType.none) {
      return false;
    }

    if (mahJong(snapshot.deck, TichuTurn(TurnType.none, const []), hand)) {
      return false;
    }

    return true;
  }

  bool shouldAutoSelectFinisher({
    required PlayerSnapshot snapshot,
    required String humanId,
    required List<Card> hand,
    required bool schupfAckPending,
    required bool hasSelectedCards,
  }) {
    if (!_isPlayTurnForHuman(snapshot, humanId, schupfAckPending)) {
      return false;
    }
    if (hasSelectedCards) return false;
    if (hand.isEmpty) return false;

    final updated = _turnRules.tryApplyTurn(
      snapshot.deck,
      hand,
      CardFace.none,
      hand: hand,
    );
    return updated.turn != TichuTurn.invalid();
  }

  /// Whether the given turn contains Mah Jong and thus requires a wish input.
  bool requiresWishInput(TichuTurn turn) =>
      turn.cards.any((card) => card.face == CardFace.mahJong);

  /// Maps cards to their hand indices (first match, no duplicates).
  Set<int> cardIndicesInHand(List<Card> hand, List<Card> cards) {
    final indices = <int>{};
    final used = <int>{};
    for (final card in cards) {
      for (var i = 0; i < hand.length; i++) {
        if (!used.contains(i) && _cardsMatchForSelection(hand[i], card)) {
          indices.add(i);
          used.add(i);
          break;
        }
      }
    }
    return indices;
  }

  bool _cardsMatchForSelection(Card handCard, Card selectedCard) {
    if (handCard == selectedCard) {
      return true;
    }

    // Suggested phoenix singles carry a dynamic play value, while the hand
    // stores phoenix at its base value. Match them by identity, not value.
    return handCard.face == CardFace.phoenix &&
        selectedCard.face == CardFace.phoenix;
  }

  /// Returns the first bomb in [hand] that can beat the current [deck], or
  /// `null` if none exists.
  TichuTurn? firstPlayableBomb(DeckState deck, List<Card> hand) =>
      _turnRules.firstPlayableBomb(deck, hand);

  bool _isPlayTurnForHuman(
    PlayerSnapshot snapshot,
    String humanId,
    bool schupfAckPending,
  ) {
    if (snapshot.phase != GamePhase.play) return false;
    if (snapshot.pendingDragonGiveBy == humanId) return false;
    if (snapshot.currentPlayerId != humanId) return false;
    if (snapshot.schupfReceipts.isNotEmpty) return false;
    if (schupfAckPending) return false;
    return true;
  }
}
