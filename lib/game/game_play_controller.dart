import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn_rules_adapter.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/wish_logic.dart';

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
      if (updated.turn != TichuTurn.InvalidTurn()) {
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

    if (mahJong(snapshot.deck, TichuTurn(TurnType.none, []), hand)) {
      return false;
    }

    return true;
  }

  bool canEnableBomb({
    required PlayerSnapshot snapshot,
    required String humanId,
    required List<Card> hand,
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
    return updated.turn != TichuTurn.InvalidTurn();
  }

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
