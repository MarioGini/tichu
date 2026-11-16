import 'package:tichu/agents/dragon_give_strategy.dart';
import 'package:tichu/agents/heuristic_options.dart';
import 'package:tichu/agents/legal_play_guard.dart';
import 'package:tichu/agents/plan_play.dart';
import 'package:tichu/agents/play_selection_strategy.dart';
import 'package:tichu/agents/play_tactics_policy.dart';
import 'package:tichu/agents/schupf_strategy.dart';
import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/agents/tichu_call_strategy.dart';
import 'package:tichu/agents/turn_scorer.dart';
import 'package:tichu/agents/wish_strategy.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

part 'smart_ai_helpers.dart';
part 'smart_ai_heuristic_turn.dart';

/// A strategic AI agent that makes intelligent decisions for all game phases.
///
/// Uses [TichuCallStrategy] for tichu/grand tichu decisions, schupfs low cards
/// to opponents, picks the lowest valid play to conserve strong cards,
/// and handles phoenix value, wish selection, and dragon give intelligently.
class SmartAiAgent extends PlayerAgent {
  @override
  final String playerId;

  final TichuCallStrategy tichuCallStrategy;

  /// Switchable heuristic rules (A/B testing); the app uses the latest.
  final HeuristicOptions options;
  final SchupfStrategy schupfStrategy;
  late final PlaySelectionStrategy playSelectionStrategy;
  final PlayTacticsPolicy playTacticsPolicy;
  final WishStrategy wishStrategy;
  final DragonGiveStrategy dragonGiveStrategy;
  CardFace? _lastSchupfedNextFace;
  int _lastSchupfRoundNumber = 0;

  SmartAiAgent(
    this.playerId, {
    this.options = HeuristicOptions.latest,
    final TichuCallStrategy? tichuCallStrategy,
    final SchupfStrategy? schupfStrategy,
    final PlaySelectionStrategy? playSelectionStrategy,
    final PlayTacticsPolicy? playTacticsPolicy,
    final WishStrategy? wishStrategy,
    final DragonGiveStrategy? dragonGiveStrategy,
  }) : tichuCallStrategy =
           tichuCallStrategy ?? DefaultTichuCallStrategy(options: options),
       schupfStrategy = schupfStrategy ?? const DefaultSchupfStrategy(),
       playTacticsPolicy = playTacticsPolicy ?? const PlayTacticsPolicy(),
       wishStrategy = wishStrategy ?? const DefaultWishStrategy(),
       dragonGiveStrategy =
           dragonGiveStrategy ?? const DefaultDragonGiveStrategy() {
    this.playSelectionStrategy =
        playSelectionStrategy ??
        DefaultPlaySelectionStrategy(
          turnScorer: TurnScorer(
            weights:
                (options.planScore
                        ? const PolicyWeights(planEfficiency: 2.5)
                        : const PolicyWeights())
                    .withOverrides(options.weights),
          ),
        );
  }

  // ---------------------------------------------------------------------------
  // Tichu / Grand Tichu
  // ---------------------------------------------------------------------------

  @override
  Future<bool> shouldCallGrandTichu(final GameSnapshot snapshot) async {
    if (_partnerAlreadyCalled(snapshot)) return false;
    return tichuCallStrategy.shouldCallGrandTichu(snapshot, playerId);
  }

  @override
  Future<bool> shouldCallTichu(final GameSnapshot snapshot) async {
    if (_partnerAlreadyCalled(snapshot)) return false;
    return tichuCallStrategy.shouldCallTichu(snapshot, playerId);
  }

  @override
  Future<bool> shouldCallTichuBeforeSchupf(final GameSnapshot snapshot) async {
    if (_partnerAlreadyCalled(snapshot)) return false;
    return tichuCallStrategy.shouldCallTichuBeforeSchupf(snapshot, playerId);
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
    final hand = List<Card>.from(snapshot.hands[playerId] ?? []);
    final deck = snapshot.deck;
    final table = TableRelationships(snapshot, playerId);

    if (hand.isEmpty) {
      return PassAction(playerId: playerId);
    }

    final generatedTurns = generateLegalTurns(deck, List<Card>.from(hand));
    // generatedTurns are already type-normalised, drawn from `hand`, and
    // satisfy validTurn(deck, .). The move generator does NOT enforce
    // active wishes, so we filter only that — much cheaper than the full
    // strictLegalTurnsFromCandidates path.
    var legalTurns = LegalPlayGuard.filterMoveGeneratorTurns(
      deck: deck,
      hand: hand,
      moveGeneratorTurns: generatedTurns,
    );

    if (legalTurns.isEmpty) {
      // Nothing beats the trick: pass. (The move generator is complete —
      // the brute-force search below never found a play it missed in 80k
      // such positions — and that search walks every subset of the hand,
      // which used to cost ~90 % of a bot's thinking time.)
      if (LegalPlayGuard.canPass(deck: deck, hand: hand)) {
        return PassAction(playerId: playerId);
      }
      // Passing is illegal, so a legal play must exist: search exhaustively.
      final recovered = LegalPlayGuard.firstLegalTurnBruteForce(
        deck: deck,
        hand: hand,
      );
      if (recovered == null) {
        throw StateError(
          'No legal turn and pass is illegal for current state.',
        );
      }
      legalTurns = [recovered];
    }

    // Partner called Tichu: support them — pass whenever allowed and never
    // go out ahead of them (a quarter of the heuristic's failed Tichus were
    // the caller's own partner finishing first). When leading, play anything
    // but the last cards.
    if (_holdBackForPartnerTichu(snapshot, table)) {
      final canPass = LegalPlayGuard.canPass(deck: deck, hand: hand);
      if (options.supportPartnerTichu && canPass) {
        return PassAction(playerId: playerId);
      }
      if (canPass &&
          legalTurns.every((final turn) => turn.cards.length == hand.length)) {
        return PassAction(playerId: playerId);
      }
      final nonFinishing = legalTurns
          .where((final turn) => turn.cards.length != hand.length)
          .toList();
      if (nonFinishing.isNotEmpty) legalTurns = nonFinishing;
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

    if (playSelectionStrategy case final FullTurnPolicy fullTurn) {
      final canPass = LegalPlayGuard.canPass(deck: deck, hand: hand);
      final selected = fullTurn.selectTurnOrPass(
        snapshot,
        legalTurns,
        deck,
        hand,
        canPass: canPass,
      );
      if (selected == null) return PassAction(playerId: playerId);
      return _buildPlayAction(snapshot, selected, deck, hand);
    }
    return _heuristicTurn(snapshot, deck, hand, table, legalTurns);
  }

  /// The action this agent would submit for playing [turn] (adds the wish
  /// when the Mah Jong is played). Used by training rollouts to try every
  /// legal turn.
  PlayTurnAction playActionFor(
    final GameSnapshot snapshot,
    final TichuTurn turn,
  ) {
    _syncRound(snapshot);
    return _buildPlayAction(
      snapshot,
      turn,
      snapshot.deck,
      List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]),
    );
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
      // Always hand off a mutable copy so downstream turn parsing can sort.
      cards: List<Card>.from(turn.cards),
      inputWish: wish,
    );
  }

  // ---------------------------------------------------------------------------
  // Wish selection
  // ---------------------------------------------------------------------------

  @override
  int selectDragonGive(final GameSnapshot snapshot) =>
      dragonGiveStrategy.selectDragonGive(snapshot, playerId);

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
