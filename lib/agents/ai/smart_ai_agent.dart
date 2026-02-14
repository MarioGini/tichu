import 'package:tichu/game/game_backend.dart';
import 'package:tichu/agents/ai/dragon_give_strategy.dart';
import 'package:tichu/agents/ai/game_state_tracker.dart';
import 'package:tichu/agents/ai/play_tactics_policy.dart';
import 'package:tichu/agents/ai/player_agent.dart';
import 'package:tichu/agents/ai/play_selection_strategy.dart';
import 'package:tichu/agents/ai/schupf_strategy.dart';
import 'package:tichu/agents/ai/table_relationships.dart';
import 'package:tichu/agents/ai/tichu_call_strategy.dart';
import 'package:tichu/agents/ai/turn_scorer.dart';
import 'package:tichu/agents/ai/wish_strategy.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

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
  final PlayTacticsPolicy playTacticsPolicy;
  final WishStrategy wishStrategy;
  final DragonGiveStrategy dragonGiveStrategy;
  CardFace? _lastSchupfedNextFace;
  int _lastSchupfRoundNumber = 0;

  SmartAiAgent(
    this.playerId, {
    GameStateTracker? gameStateTracker,
    TichuCallStrategy? tichuCallStrategy,
    SchupfStrategy? schupfStrategy,
    PlaySelectionStrategy? playSelectionStrategy,
    PlayTacticsPolicy? playTacticsPolicy,
    WishStrategy? wishStrategy,
    DragonGiveStrategy? dragonGiveStrategy,
  }) : gameStateTracker = gameStateTracker ?? GameStateTracker(),
       tichuCallStrategy =
           tichuCallStrategy ?? const DefaultTichuCallStrategy(),
       schupfStrategy = schupfStrategy ?? const DefaultSchupfStrategy(),
       playTacticsPolicy = playTacticsPolicy ?? const PlayTacticsPolicy(),
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
    _lastSchupfedNextFace = action.toLeft.face;
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
    final table = TableRelationships(snapshot, playerId);

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

    final partnerPass = playTacticsPolicy.selectPartnerSupportPass(
      playerId: playerId,
      snapshot: snapshot,
      deck: deck,
      hand: hand,
      table: table,
    );
    if (partnerPass != null) {
      return partnerPass;
    }

    final partnerLead = playTacticsPolicy.selectPartnerFinishLead(
      snapshot: snapshot,
      legalTurns: legalTurns,
      isLeading: isLeading,
      table: table,
    );
    if (partnerLead != null) {
      return _buildPlayAction(snapshot, partnerLead, deck, hand);
    }

    final mahjongLead = playTacticsPolicy.selectMahjongLeadTurn(
      legalTurns: legalTurns,
      deck: deck,
      hand: hand,
      isLeading: isLeading,
      selectPlay: (options) =>
          playSelectionStrategy.selectPlay(snapshot, options, deck, hand),
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

    final wishPreferredTurns = playTacticsPolicy.wishPreferredTurns(
      legalTurns: legalTurns,
      deck: deck,
    );
    if (wishPreferredTurns.isNotEmpty) {
      final selected = playSelectionStrategy.selectPlay(
        snapshot,
        wishPreferredTurns,
        deck,
        hand,
      );
      return _buildPlayAction(snapshot, selected, deck, hand);
    }

    final validPlays = playTacticsPolicy.filterWishValidPlays(
      deck: deck,
      legalTurns: legalTurns,
      hand: hand,
    );

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

  CardFace _selectMahjongWish(
    GameSnapshot snapshot,
    List<Card> hand,
    DeckState deck,
  ) {
    final preferredWish = _lastSchupfedNextFace;

    final wish = wishStrategy.selectWish(
      snapshot,
      hand,
      deck,
      preferredFace: preferredWish,
    );
    if (wish != CardFace.none) {
      return wish;
    }

    return CardFace.none;
  }

  void _syncRound(GameSnapshot snapshot) {
    if (_lastSchupfRoundNumber != snapshot.scoreState.roundNumber) {
      _lastSchupfRoundNumber = snapshot.scoreState.roundNumber;
      _lastSchupfedNextFace = null;
    }
  }
}
