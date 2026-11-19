import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn_rules_adapter.dart';

/// A decision the engine is waiting for from one player.
///
/// Shared by every driver of [PlayerAgent]s — the app's `AiTurnRunner` and
/// the headless training simulator — so bots behave identically in the app
/// and in training. Drivers add their own concerns around it (UI delays and
/// confirmation in the app; exploration and logging in training).
sealed class DecisionRequest {
  final String playerId;
  const DecisionRequest(this.playerId);
}

/// The player must acknowledge the cards they received in the schupf.
class SchupfReceiptRequest extends DecisionRequest {
  const SchupfReceiptRequest(super.playerId);
}

/// The player must decide whether to call Grand Tichu (8 cards seen).
class GrandTichuRequest extends DecisionRequest {
  const GrandTichuRequest(super.playerId);
}

/// Before anyone passes cards: may the player call Tichu now (so the
/// partner can react in the exchange)? Only asked when the driver tracks
/// these decisions (`preSchupfDecided` in [AgentDecisions.next]).
class PreSchupfTichuRequest extends DecisionRequest {
  const PreSchupfTichuRequest(super.playerId);
}

/// The player must choose the three cards to pass.
class SchupfRequest extends DecisionRequest {
  const SchupfRequest(super.playerId);
}

/// The player won a trick with the Dragon and must give it away.
class DragonGiveRequest extends DecisionRequest {
  final List<String> opponentIds;
  const DragonGiveRequest(super.playerId, this.opponentIds);
}

/// The player holds a bomb that beats the trick on the table and may play it
/// out of turn ("interrupt"), before the player to move acts. Answered with
/// a bomb or a [DeclineBombAction] (asked again after the next play/pass).
class BombInterruptRequest extends DecisionRequest {
  /// The player's bombs that beat the current trick.
  final List<TichuTurn> bombs;
  const BombInterruptRequest(super.playerId, this.bombs);
}

/// It is the player's turn in the play phase (play, pass or call Tichu).
class TurnRequest extends DecisionRequest {
  const TurnRequest(super.playerId);
}

abstract final class AgentDecisions {
  /// The next pending decision among players accepted by [include] (all
  /// players when null), or null when none of them has to act.
  ///
  /// In the Grand Tichu phase this advances `state.currentPlayerIndex` past
  /// players who already decided (the engine expects drivers to do so).
  ///
  /// When [preSchupfDecided] is given, every player not in it (and without a
  /// call yet) is first asked a [PreSchupfTichuRequest] in the schupf phase;
  /// the driver adds the player to the set once asked.
  ///
  /// In the play phase every other player holding a bomb that beats the
  /// trick is first offered a [BombInterruptRequest] (once per bomb window,
  /// in seat order after the player to move), unless [bombInterrupts] is
  /// false.
  static DecisionRequest? next(
    final GameEngine engine,
    final GameEngineState state, {
    final bool Function(GamePlayer player)? include,
    final Set<String>? preSchupfDecided,
    final bool bombInterrupts = true,
  }) {
    bool accepts(final GamePlayer p) => include == null || include(p);

    for (final player in state.players) {
      final receipts = state.schupfReceipts[player.id];
      if (receipts != null && receipts.isNotEmpty && accepts(player)) {
        return SchupfReceiptRequest(player.id);
      }
    }

    if (state.phase == GamePhase.grandTichu) {
      for (var i = 0; i < state.players.length; i++) {
        final current = state.players[state.currentPlayerIndex];
        if (!state.grandTichuDecisions.containsKey(current.id)) {
          return accepts(current) ? GrandTichuRequest(current.id) : null;
        }
        state.currentPlayerIndex =
            (state.currentPlayerIndex + 1) % state.players.length;
      }
      return null;
    }
    if (state.phase == GamePhase.schupf) {
      if (preSchupfDecided != null) {
        final calls = state.scoreTracker.state.tichuCalls;
        for (final player in state.players) {
          if (accepts(player) &&
              !preSchupfDecided.contains(player.id) &&
              !state.schupfSelections.containsKey(player.id) &&
              (calls[player.id] ?? TichuCall.none) == TichuCall.none) {
            return PreSchupfTichuRequest(player.id);
          }
        }
      }
      for (final player in state.players) {
        if (!state.schupfSelections.containsKey(player.id) && accepts(player)) {
          return SchupfRequest(player.id);
        }
      }
      return null;
    }

    final dragonBy = state.pendingDragonGiveBy;
    if (dragonBy != null) {
      final player = state.players.firstWhere((final p) => p.id == dragonBy);
      if (!accepts(player)) return null;
      return DragonGiveRequest(dragonBy, engine.opponentIds(state, dragonBy));
    }

    if (state.phase != GamePhase.play) return null;
    if (bombInterrupts) {
      final interrupt = nextBombInterrupt(state, include: include);
      if (interrupt != null) return interrupt;
    }
    final current = state.players[state.currentPlayerIndex];
    return accepts(current) ? TurnRequest(current.id) : null;
  }

  static final _rules = TurnRulesAdapter();

  /// The bombs in [playerId]'s hand that beat the trick on the table.
  static List<TichuTurn> beatingBombs(
    final GameEngineState state,
    final String playerId,
  ) => beatingBombsIn(state.deck, state.hands[playerId] ?? const <Card>[]);

  /// The bombs in [hand] that beat [deck]'s trick (the legal actions of an
  /// out-of-turn decision, besides waiting).
  static List<TichuTurn> beatingBombsIn(
    final DeckState deck,
    final List<Card> hand,
  ) {
    if (hand.length < 4) return const [];
    return [
      for (final bomb in _rules.bombsInHand(hand))
        if (_rules
                .tryApplyTurn(deck, bomb.cards, CardFace.none, hand: hand)
                .turn !=
            TichuTurn.InvalidTurn())
          bomb,
    ];
  }

  /// The next player (after the player to move, in seat order) who may bomb
  /// out of turn and has not declined in the current bomb window.
  static BombInterruptRequest? nextBombInterrupt(
    final GameEngineState state, {
    final bool Function(GamePlayer player)? include,
  }) {
    if (state.pendingDragonGiveBy != null) return null;
    final type = state.deck.turn.type;
    if (type == TurnType.empty ||
        type == TurnType.none ||
        type == TurnType.dog) {
      return null;
    }
    final window = state.bombWindow;
    final n = state.players.length;
    for (var k = 1; k < n; k++) {
      final player = state.players[(state.currentPlayerIndex + k) % n];
      if (player.id == state.lastPlayedBy ||
          state.finishedPlayers.contains(player.id) ||
          state.bombDeclines[player.id] == window ||
          (include != null && !include(player))) {
        continue;
      }
      final bombs = beatingBombs(state, player.id);
      if (bombs.isNotEmpty) return BombInterruptRequest(player.id, bombs);
    }
    return null;
  }

  /// Ask [agent] for its answer to [request] and return it as an action.
  /// Returns null only for a [PreSchupfTichuRequest] answered with "no".
  ///
  /// May throw [StateError] when the agent has no legal turn.
  static Future<GameAction?> resolve(
    final DecisionRequest request,
    final PlayerAgent agent,
    final GameSnapshot snapshot,
    final GameEngineState state,
  ) async {
    switch (request) {
      case SchupfReceiptRequest(:final playerId):
        return AcknowledgeSchupfAction(playerId: playerId);
      case GrandTichuRequest(:final playerId):
        return GrandTichuDecisionAction(
          playerId: playerId,
          call: await agent.shouldCallGrandTichu(snapshot),
        );
      case PreSchupfTichuRequest(:final playerId):
        return await agent.shouldCallTichuBeforeSchupf(snapshot)
            ? CallTichuAction(playerId: playerId)
            : null;
      case SchupfRequest():
        return agent.selectSchupfCards(snapshot);
      case DragonGiveRequest(:final playerId, :final opponentIds):
        return GiveDragonAction(
          playerId: playerId,
          targetPlayerId: dragonTarget(
            state: state,
            opponentIds: opponentIds,
            preferredSeat: agent.selectDragonGive(snapshot),
          ),
        );
      case BombInterruptRequest(:final playerId, :final bombs):
        final cards = await agent.selectInterruptBomb(snapshot, bombs);
        return cards == null
            ? DeclineBombAction(playerId: playerId)
            : PlayTurnAction(playerId: playerId, cards: cards);
      case TurnRequest():
        return agent.selectAction(snapshot);
    }
  }

  /// The opponent sitting at [preferredSeat], or the first opponent when the
  /// seat is not an opponent's.
  static String dragonTarget({
    required final GameEngineState state,
    required final List<String> opponentIds,
    required final int? preferredSeat,
  }) {
    if (opponentIds.isEmpty) {
      throw StateError('No valid dragon target available.');
    }
    for (final player in state.players) {
      if (player.seat == preferredSeat && opponentIds.contains(player.id)) {
        return player.id;
      }
    }
    return opponentIds.first;
  }
}
