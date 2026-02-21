import 'package:tichu/agents/dragon_give_strategy.dart';
import 'package:tichu/agents/game_state_tracker.dart';
import 'package:tichu/agents/play_selection_strategy.dart';
import 'package:tichu/agents/play_tactics_policy.dart';
import 'package:tichu/agents/schupf_strategy.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/agents/tichu_call_strategy.dart';
import 'package:tichu/agents/turn_scorer.dart';
import 'package:tichu/agents/wish_strategy.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// A strategic AI agent that makes intelligent decisions for all game phases.
///
/// Uses [TichuCallStrategy] for tichu/grand tichu decisions, schupfs low cards
/// to opponents, picks the lowest valid play to conserve strong cards,
/// and handles phoenix value, wish selection, and dragon give intelligently.
class SmartAiAgent extends PlayerAgent {
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
    final GameStateTracker? gameStateTracker,
    final TichuCallStrategy? tichuCallStrategy,
    final SchupfStrategy? schupfStrategy,
    final PlaySelectionStrategy? playSelectionStrategy,
    final PlayTacticsPolicy? playTacticsPolicy,
    final WishStrategy? wishStrategy,
    final DragonGiveStrategy? dragonGiveStrategy,
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
  Future<bool> shouldCallGrandTichu(final GameSnapshot snapshot) async => false;

  @override
  Future<bool> shouldCallTichu(final GameSnapshot snapshot) async {
    if (_partnerAlreadyCalled(snapshot)) return false;
    return tichuCallStrategy.shouldCallTichu(snapshot, playerId);
  }

  bool _partnerAlreadyCalled(final GameSnapshot snapshot) {
    final table = TableRelationships(snapshot, playerId);
    final partnerId = table.partnerId;
    if (partnerId == null) return false;
    final partnerCall =
        snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none;
    return partnerCall != TichuCall.none;
  }

  // ---------------------------------------------------------------------------
  // Schupfen
  // ---------------------------------------------------------------------------

  @override
  Future<SchupfAction> selectSchupfCards(final GameSnapshot snapshot) async {
    _syncRound(snapshot);
    final action = await schupfStrategy.selectSchupfCards(snapshot, playerId);
    _lastSchupfedNextFace = action.toLeft.face;
    return action;
  }

  // ---------------------------------------------------------------------------
  // Play selection
  // ---------------------------------------------------------------------------

  @override
  Future<GameAction> selectTurn(final GameSnapshot snapshot) async {
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

    final finishingTurns = legalTurns
        .where((final turn) => turn.cards.length == hand.length)
        .toList();
    if (finishingTurns.isNotEmpty) {
      final selected = playSelectionStrategy.selectPlay(
        snapshot,
        finishingTurns,
        deck,
        hand,
      );
      return _buildPlayAction(snapshot, selected, deck, hand);
    }

    final isLeading =
        deck.turn.type == TurnType.empty ||
        deck.turn.type == TurnType.none ||
        deck.turn.type == TurnType.dog;
    final isGameOpeningLead =
        snapshot.scoreState.roundNumber == 1 &&
        snapshot.lastPlayedBy == null &&
        snapshot.lastPlayedTurn == null;

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

    final mahjongLead = playTacticsPolicy.selectMahjongLeadTurn(
      legalTurns: legalTurns,
      deck: deck,
      hand: hand,
      isLeading: isLeading && isGameOpeningLead,
      selectPlay: (final options) =>
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

    final partnerLead = playTacticsPolicy.selectPartnerFinishLead(
      snapshot: snapshot,
      legalTurns: legalTurns,
      isLeading: isLeading,
      table: table,
    );
    if (partnerLead != null) {
      return _buildPlayAction(snapshot, partnerLead, deck, hand);
    }

    final earlyDog = playTacticsPolicy.selectEarlyDogLead(
      legalTurns: legalTurns,
      isLeading: isLeading,
    );
    if (earlyDog != null) {
      return _buildPlayAction(snapshot, earlyDog, deck, hand);
    }

    final partnerGrandDogLead = playTacticsPolicy
        .selectPartnerGrandTichuDogLead(
          playerId: playerId,
          snapshot: snapshot,
          legalTurns: legalTurns,
          isLeading: isLeading,
          table: table,
        );
    if (partnerGrandDogLead != null) {
      return _buildPlayAction(snapshot, partnerGrandDogLead, deck, hand);
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

    var validPlays = playTacticsPolicy.filterWishValidPlays(
      deck: deck,
      legalTurns: legalTurns,
      hand: hand,
    );

    validPlays = _filterLowSinglePhoenixResponses(deck, validPlays);

    if (validPlays.isEmpty) {
      return PassAction(playerId: playerId);
    }

    final opponentThreatWinning = playTacticsPolicy
        .opponentTichuNearFinishWinning(
          playerId: playerId,
          snapshot: snapshot,
          deck: deck,
          table: table,
        );
    if (!opponentThreatWinning) {
      final singletonResponse = playTacticsPolicy.selectSingletonResponse(
        legalTurns: validPlays,
        deck: deck,
        hand: hand,
      );
      if (singletonResponse != null) {
        return _buildPlayAction(snapshot, singletonResponse, deck, hand);
      }
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
    final GameSnapshot snapshot,
    final TichuTurn turn,
    final DeckState deck,
    final List<Card> hand, {
    final bool suppressWish = false,
  }) {
    // Determine wish if we're playing the Mah Jong.
    var wish = CardFace.none;
    if (turn.cards.any((final c) => c.face == CardFace.mahJong)) {
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

  List<TichuTurn> _filterLowSinglePhoenixResponses(
    final DeckState deck,
    final List<TichuTurn> plays,
  ) {
    if (deck.turn.type != TurnType.single) {
      return plays;
    }

    final kingValue = Card.getValue(CardFace.king);
    if (deck.turn.value >= kingValue) {
      return plays;
    }

    return plays.where((final turn) {
      if (turn.type != TurnType.single) {
        return true;
      }
      return !turn.cards.any((final card) => card.face == CardFace.phoenix);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Phoenix value
  // ---------------------------------------------------------------------------

  /// Select phoenix value for a play. The move generator already assigns
  /// appropriate phoenix values (deck.value + 0.5 for singles, matching value
  /// for combos), so this is mainly for the interface contract.
  double selectPhoenixValue(
    final DeckState deck,
    final List<Card> selectedCards,
  ) {
    final phoenix = selectedCards
        .where((final c) => c.face == CardFace.phoenix)
        .toList();
    if (phoenix.isEmpty) return 0;
    return phoenix.first.value;
  }

  // ---------------------------------------------------------------------------
  // Wish selection
  // ---------------------------------------------------------------------------

  @override
  int selectDragonGive(final GameSnapshot snapshot) {
    gameStateTracker.update(snapshot, playerId);
    return dragonGiveStrategy.selectDragonGive(snapshot, playerId);
  }

  CardFace _selectMahjongWish(
    final GameSnapshot snapshot,
    final List<Card> hand,
    final DeckState deck,
  ) {
    final preferredWish = _lastSchupfedNextFace;

    return wishStrategy.selectWish(
      snapshot,
      hand,
      deck,
      preferredFace: preferredWish,
    );
  }

  void _syncRound(final GameSnapshot snapshot) {
    if (_lastSchupfRoundNumber != snapshot.scoreState.roundNumber) {
      _lastSchupfRoundNumber = snapshot.scoreState.roundNumber;
      _lastSchupfedNextFace = null;
    }
  }
}
