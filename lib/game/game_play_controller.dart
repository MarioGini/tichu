import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/wish_logic.dart';
import 'package:tichu/game/turn_rules_adapter.dart';

class GamePlayController {
  final TurnRulesAdapter _turnRules;

  GamePlayController({final TurnRulesAdapter? turnRules})
    : _turnRules = turnRules ?? TurnRulesAdapter();

  TichuTurn? resolveSelectedTurn({
    required final PlayerSnapshot snapshot,
    required final List<Card> selectedCards,
    required final List<Card> hand,
  }) {
    if (selectedCards.isEmpty) {
      return null;
    }

    final selectedTurn = _turnRules.detectTurn(selectedCards);
    if (selectedTurn == TichuTurn.InvalidTurn()) {
      return null;
    }

    final updated = _turnRules.tryApplyTurn(
      snapshot.deck,
      selectedCards,
      CardFace.none,
      hand: hand,
    );
    if (updated.turn == TichuTurn.InvalidTurn()) {
      return null;
    }

    return selectedTurn;
  }

  bool canPlaySelected({
    required final PlayerSnapshot snapshot,
    required final String humanId,
    required final List<Card> hand,
    required final List<Card> selectedCards,
    required final bool schupfAckPending,
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
    required final PlayerSnapshot snapshot,
    required final String humanId,
    required final List<Card> hand,
    required final bool schupfAckPending,
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
      if (updated.turn != TichuTurn.InvalidTurn()) {
        return true;
      }
    }

    return false;
  }

  bool canPass({
    required final PlayerSnapshot snapshot,
    required final String humanId,
    required final List<Card> hand,
    required final bool schupfAckPending,
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

  bool canEnableBomb({
    required final PlayerSnapshot snapshot,
    required final String humanId,
    required final List<Card> hand,
  }) {
    if (snapshot.phase != GamePhase.play) return false;
    if (snapshot.pendingDragonGiveBy == humanId) return false;
    if (!_turnRules.hasBomb(hand)) return false;

    final isHumanTurn = snapshot.currentPlayerId == humanId;
    final deckType = snapshot.deck.turn.type;
    if (!isHumanTurn &&
        (deckType == TurnType.empty || deckType == TurnType.none)) {
      return false;
    }

    return true;
  }

  bool shouldAutoSelectFinisher({
    required final PlayerSnapshot snapshot,
    required final String humanId,
    required final List<Card> hand,
    required final bool schupfAckPending,
    required final bool hasSelectedCards,
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
    return updated.turn != TichuTurn.InvalidTurn();
  }

  /// Whether the given turn contains Mah Jong and thus requires a wish input.
  bool requiresWishInput(final TichuTurn turn) =>
      turn.cards.any((final card) => card.face == CardFace.mahJong);

  /// Maps cards to their hand indices (first match, no duplicates).
  Set<int> cardIndicesInHand(final List<Card> hand, final List<Card> cards) {
    final indices = <int>{};
    final used = <int>{};
    for (final card in cards) {
      for (var i = 0; i < hand.length; i++) {
        if (!used.contains(i) && hand[i] == card) {
          indices.add(i);
          used.add(i);
          break;
        }
      }
    }
    return indices;
  }

  /// Returns the first bomb in [hand] that can beat the current [deck], or
  /// `null` if none exists.
  TichuTurn? firstPlayableBomb(final DeckState deck, final List<Card> hand) =>
      _turnRules.firstPlayableBomb(deck, hand);

  bool _isPlayTurnForHuman(
    final PlayerSnapshot snapshot,
    final String humanId,
    final bool schupfAckPending,
  ) {
    if (snapshot.phase != GamePhase.play) return false;
    if (snapshot.pendingDragonGiveBy == humanId) return false;
    if (snapshot.currentPlayerId != humanId) return false;
    if (snapshot.schupfReceipts.isNotEmpty) return false;
    if (schupfAckPending) return false;
    return true;
  }
}
