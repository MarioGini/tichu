import 'package:tichu/services/game_backend.dart';
import 'package:tichu/view_model/ai/dragon_give_strategy.dart';
import 'package:tichu/view_model/ai/game_state_tracker.dart';
import 'package:tichu/view_model/ai/player_agent.dart';
import 'package:tichu/view_model/ai/play_selection_strategy.dart';
import 'package:tichu/view_model/ai/schupf_strategy.dart';
import 'package:tichu/view_model/ai/tichu_call_strategy.dart';
import 'package:tichu/view_model/ai/turn_scorer.dart';
import 'package:tichu/view_model/ai/wish_strategy.dart';
import 'package:tichu/view_model/scoring/score_tracker.dart';
import 'package:tichu/view_model/turn/move_generator.dart';
import 'package:tichu/view_model/turn/tichu_data.dart';
import 'package:tichu/view_model/turn/wish_logic.dart';

/// A strategic AI agent that makes intelligent decisions for all game phases.
///
/// Uses [HandEvaluator] for tichu/grand tichu decisions, schupfs low cards
/// to opponents, picks the lowest valid play to conserve strong cards,
/// and handles phoenix value, wish selection, and dragon give intelligently.
class SmartAiAgent implements PlayerAgent {
  @override
  final String playerId;

  final GameStateTracker gameStateTracker;
  final TichuCallStrategy tichuCallStrategy;
  final SchupfStrategy schupfStrategy;
  late final PlaySelectionStrategy playSelectionStrategy;
  final WishStrategy wishStrategy;
  final DragonGiveStrategy dragonGiveStrategy;
  CardFace? _lastSchupfedRightFace;
  int _lastSchupfRoundNumber = 0;

  SmartAiAgent(
    this.playerId, {
    GameStateTracker? gameStateTracker,
    TichuCallStrategy? tichuCallStrategy,
    SchupfStrategy? schupfStrategy,
    PlaySelectionStrategy? playSelectionStrategy,
    WishStrategy? wishStrategy,
    DragonGiveStrategy? dragonGiveStrategy,
  }) : gameStateTracker = gameStateTracker ?? GameStateTracker(),
       tichuCallStrategy =
           tichuCallStrategy ?? const DefaultTichuCallStrategy(),
       schupfStrategy = schupfStrategy ?? const DefaultSchupfStrategy(),
       wishStrategy = wishStrategy ?? const DefaultWishStrategy(),
       dragonGiveStrategy =
           dragonGiveStrategy ?? const DefaultDragonGiveStrategy() {
    this.playSelectionStrategy =
        playSelectionStrategy ??
        DefaultPlaySelectionStrategy(
          turnScorer: TurnScorer(tracker: this.gameStateTracker),
        );
  }

  // ---------------------------------------------------------------------------
  // Tichu / Grand Tichu
  // ---------------------------------------------------------------------------

  @override
  Future<bool> shouldCallGrandTichu(GameSnapshot snapshot) async {
    return tichuCallStrategy.shouldCallGrandTichu(snapshot, playerId);
  }

  @override
  Future<bool> shouldCallTichu(GameSnapshot snapshot) async {
    return tichuCallStrategy.shouldCallTichu(snapshot, playerId);
  }

  // ---------------------------------------------------------------------------
  // Schupfen
  // ---------------------------------------------------------------------------

  @override
  Future<SchupfAction> selectSchupfCards(GameSnapshot snapshot) async {
    _syncRound(snapshot);
    final action = await schupfStrategy.selectSchupfCards(snapshot, playerId);
    _lastSchupfedRightFace = action.toRight.face;
    return action;
  }

  // ---------------------------------------------------------------------------
  // Play selection
  // ---------------------------------------------------------------------------

  @override
  Future<GameAction> selectTurn(GameSnapshot snapshot) async {
    _syncRound(snapshot);
    gameStateTracker.update(snapshot, playerId);
    final hand = List<Card>.from(snapshot.hands[playerId] ?? []);
    final deck = snapshot.deck;

    if (hand.isEmpty) {
      return PassAction(playerId: playerId);
    }

    final legalTurns = generateLegalTurns(deck, hand);
    if (legalTurns.isEmpty) {
      return PassAction(playerId: playerId);
    }

    final isLeading =
        deck.turn.type == TurnType.empty ||
        deck.turn.type == TurnType.none ||
        deck.turn.type == TurnType.dog;

    final partnerId = _partnerId(snapshot);
    if (partnerId != null) {
      final partnerCall =
          snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none;
      final partnerCards = (snapshot.hands[partnerId] ?? const <Card>[]).length;
      if (partnerCall != TichuCall.none && partnerCards == 1 && isLeading) {
        final singles = legalTurns
            .where((turn) => turn.type == TurnType.single)
            .toList();
        if (singles.isNotEmpty) {
          singles.sort((a, b) => a.value.compareTo(b.value));
          final nonDragon = singles.where(
            (turn) => !turn.cards.any((c) => c.face == CardFace.dragon),
          );
          final selected = nonDragon.isNotEmpty
              ? nonDragon.first
              : singles.first;
          return _buildPlayAction(snapshot, selected, deck, hand);
        }
      }
      if (partnerCall != TichuCall.none &&
          snapshot.lastPlayedBy == partnerId &&
          partnerCards <= 5 &&
          hand.length > 1 &&
          deck.turn.type != TurnType.empty &&
          deck.turn.type != TurnType.none) {
        return PassAction(playerId: playerId);
      }
    }

    final mahjongLead = _selectMahjongLeadTurn(
      snapshot,
      legalTurns,
      deck,
      hand,
      isLeading,
    );
    if (mahjongLead != null) {
      return _buildPlayAction(
        snapshot,
        mahjongLead,
        deck,
        hand,
        suppressWish: mahjongLead.type == TurnType.straight,
      );
    }

    // --- Wish enforcement: if there's an active wish, prefer plays containing
    // the wished card.
    if (deck.wish != CardFace.none) {
      final wishTurns = legalTurns
          .where((turn) => turn.cards.any((card) => card.face == deck.wish))
          .toList();
      if (wishTurns.isNotEmpty) {
        final selected = playSelectionStrategy.selectPlay(
          snapshot,
          wishTurns,
          deck,
          hand,
        );
        return _buildPlayAction(snapshot, selected, deck, hand);
      }
    }

    // --- Check if we MUST play the wish but didn't select it.
    // Filter out plays that would violate the wish rule.
    final validPlays = <TichuTurn>[];
    for (final turn in legalTurns) {
      if (!mahJong(deck, turn, hand)) {
        validPlays.add(turn);
      }
    }

    if (validPlays.isEmpty) {
      return PassAction(playerId: playerId);
    }

    // --- Strategic play selection
    final selected = playSelectionStrategy.selectPlay(
      snapshot,
      validPlays,
      deck,
      hand,
    );
    return _buildPlayAction(snapshot, selected, deck, hand);
  }

  /// Build a [PlayTurnAction] from the selected turn, adding wish/phoenix
  /// metadata as needed.
  PlayTurnAction _buildPlayAction(
    GameSnapshot snapshot,
    TichuTurn turn,
    DeckState deck,
    List<Card> hand, {
    bool suppressWish = false,
  }) {
    // Determine wish if we're playing the Mah Jong.
    var wish = CardFace.none;
    if (turn.cards.any((c) => c.face == CardFace.mahJong)) {
      if (!suppressWish) {
        wish = _selectMahjongWish(snapshot, hand, deck);
      }
    }

    return PlayTurnAction(
      playerId: playerId,
      cards: turn.cards,
      inputWish: wish,
    );
  }

  // ---------------------------------------------------------------------------
  // Phoenix value
  // ---------------------------------------------------------------------------

  /// Select phoenix value for a play. The move generator already assigns
  /// appropriate phoenix values (deck.value + 0.5 for singles, matching value
  /// for combos), so this is mainly for the interface contract.
  double selectPhoenixValue(DeckState deck, List<Card> selectedCards) {
    final phoenix = selectedCards
        .where((c) => c.face == CardFace.phoenix)
        .toList();
    if (phoenix.isEmpty) return 0;
    return phoenix.first.value;
  }

  // ---------------------------------------------------------------------------
  // Wish selection
  // ---------------------------------------------------------------------------

  @override
  int selectDragonGive(GameSnapshot snapshot) {
    gameStateTracker.update(snapshot, playerId);
    return dragonGiveStrategy.selectDragonGive(snapshot, playerId);
  }

  TichuTurn? _selectMahjongLeadTurn(
    GameSnapshot snapshot,
    List<TichuTurn> legalTurns,
    DeckState deck,
    List<Card> hand,
    bool isLeading,
  ) {
    if (!isLeading || deck.wish != CardFace.none) {
      return null;
    }
    if (!hand.any((c) => c.face == CardFace.mahJong)) {
      return null;
    }

    final mahjongTurns = legalTurns
        .where((turn) => turn.cards.any((c) => c.face == CardFace.mahJong))
        .toList();
    if (mahjongTurns.isEmpty) {
      return null;
    }

    final mahjongStraights = mahjongTurns
        .where((turn) => turn.type == TurnType.straight)
        .toList();
    if (mahjongStraights.isNotEmpty) {
      return playSelectionStrategy.selectPlay(
        snapshot,
        mahjongStraights,
        deck,
        hand,
      );
    }

    return playSelectionStrategy.selectPlay(snapshot, mahjongTurns, deck, hand);
  }

  CardFace _selectMahjongWish(
    GameSnapshot snapshot,
    List<Card> hand,
    DeckState deck,
  ) {
    final schupfedRight = _lastSchupfedRightFace;
    if (schupfedRight != null && !_isSpecialWish(schupfedRight)) {
      final haveWish = hand.any((c) => c.face == schupfedRight);
      if (!haveWish) {
        return schupfedRight;
      }
    }

    final wish = wishStrategy.selectWish(snapshot, hand, deck);
    if (wish != CardFace.none) {
      return wish;
    }

    return CardFace.none;
  }

  bool _isSpecialWish(CardFace face) {
    return face == CardFace.none ||
        face == CardFace.mahJong ||
        face == CardFace.dragon ||
        face == CardFace.phoenix ||
        face == CardFace.dog;
  }

  void _syncRound(GameSnapshot snapshot) {
    if (_lastSchupfRoundNumber != snapshot.scoreState.roundNumber) {
      _lastSchupfRoundNumber = snapshot.scoreState.roundNumber;
      _lastSchupfedRightFace = null;
    }
  }

  String? _partnerId(GameSnapshot snapshot) {
    final mySeat = snapshot.players.firstWhere((p) => p.id == playerId).seat;
    for (final player in snapshot.players) {
      if (player.id == playerId) continue;
      if (player.seat % 2 == mySeat % 2) {
        return player.id;
      }
    }
    return null;
  }
}
