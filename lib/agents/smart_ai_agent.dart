import 'package:tichu/agents/dragon_give_strategy.dart';
import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/agents/heuristic_options.dart';
import 'package:tichu/agents/legal_play_guard.dart';
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

  /// `TurnScorer` weight overrides (A/B testing); the app uses the latest.
  final HeuristicOptions options;
  final SchupfStrategy schupfStrategy;
  late final PlaySelectionStrategy playSelectionStrategy;
  final PlayTacticsPolicy playTacticsPolicy;
  final WishStrategy wishStrategy;
  final DragonGiveStrategy dragonGiveStrategy;

  /// Decision-time endgame search (run by the driver, which can fork the
  /// game: see `EndgameSearcher`); null = play the policy's move as is.
  final EndgameSearch? endgameSearch;
  CardFace? _lastSchupfedNextFace;
  int _lastSchupfRoundNumber = 0;

  SmartAiAgent(
    this.playerId, {
    this.options = HeuristicOptions.latest,
    this.endgameSearch,
    TichuCallStrategy? tichuCallStrategy,
    SchupfStrategy? schupfStrategy,
    PlaySelectionStrategy? playSelectionStrategy,
    PlayTacticsPolicy? playTacticsPolicy,
    WishStrategy? wishStrategy,
    DragonGiveStrategy? dragonGiveStrategy,
  }) : tichuCallStrategy =
           tichuCallStrategy ?? const DefaultTichuCallStrategy(),
       schupfStrategy = schupfStrategy ?? const DefaultSchupfStrategy(),
       playTacticsPolicy = playTacticsPolicy ?? const PlayTacticsPolicy(),
       wishStrategy = wishStrategy ?? const DefaultWishStrategy(),
       dragonGiveStrategy =
           dragonGiveStrategy ?? const DefaultDragonGiveStrategy() {
    this.playSelectionStrategy =
        playSelectionStrategy ??
        DefaultPlaySelectionStrategy(
          turnScorer: TurnScorer(
            weights: const PolicyWeights().withOverrides(options.weights),
          ),
        );
  }

  // ---------------------------------------------------------------------------
  // Tichu / Grand Tichu
  // ---------------------------------------------------------------------------

  @override
  Future<bool> shouldCallGrandTichu(GameSnapshot snapshot) async {
    if (_partnerAlreadyCalled(snapshot)) return false;
    return tichuCallStrategy.shouldCallGrandTichu(snapshot, playerId);
  }

  @override
  Future<bool> shouldCallTichu(GameSnapshot snapshot) async {
    if (_partnerAlreadyCalled(snapshot)) return false;
    return tichuCallStrategy.shouldCallTichu(snapshot, playerId);
  }

  @override
  Future<bool> shouldCallTichuBeforeSchupf(GameSnapshot snapshot) async {
    if (_partnerAlreadyCalled(snapshot)) return false;
    return tichuCallStrategy.shouldCallTichuBeforeSchupf(snapshot, playerId);
  }

  /// Tichu may be called until the player's first card. The decision waits
  /// for the turn in which the bot plays its first card (while it passes it
  /// keeps the option and sees more of the round).
  @override
  Future<GameAction> selectAction(GameSnapshot snapshot) async {
    if (!canStillCallTichu(snapshot)) return selectTurn(snapshot);
    final turn = await selectTurn(snapshot);
    if (turn is PassAction) return turn;
    if (await shouldCallTichu(snapshot)) {
      return CallTichuAction(playerId: playerId);
    }
    return turn;
  }

  /// No call yet and no card played yet this round.
  bool canStillCallTichu(GameSnapshot snapshot) =>
      (snapshot.canCallTichuByPlayer[playerId] ?? false) &&
      (snapshot.scoreState.tichuCalls[playerId] ?? TichuCall.none) ==
          TichuCall.none;

  bool _partnerAlreadyCalled(GameSnapshot snapshot) {
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
    final hand = List<Card>.from(snapshot.hands[playerId] ?? []);
    final deck = snapshot.deck;
    final table = TableRelationships(snapshot, playerId);
    final turnOptions = _turnOptions(snapshot, hand, table);
    if (turnOptions.forced case final forced?) return forced;
    final legalTurns = turnOptions.turns;

    final finishingTurns = legalTurns
        .where((turn) => turn.cards.length == hand.length)
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
      final selected = fullTurn.selectTurnOrPass(
        snapshot,
        legalTurns,
        deck,
        hand,
        canPass: turnOptions.canPass,
      );
      if (selected == null) return PassAction(playerId: playerId);
      return _buildPlayAction(snapshot, selected, deck, hand);
    }
    return _heuristicTurn(snapshot, deck, hand, table, legalTurns);
  }

  /// The turns [selectTurn] chooses among: the wish-filtered legal turns
  /// after the partner-Tichu guard, and whether passing is legal. `forced`
  /// is set when there is nothing to choose (empty hand, nothing beats the
  /// trick, or the guard passes).
  ({List<TichuTurn> turns, bool canPass, GameAction? forced}) _turnOptions(
    GameSnapshot snapshot,
    List<Card> hand,
    TableRelationships table,
  ) {
    final deck = snapshot.deck;
    final pass = PassAction(playerId: playerId);
    if (hand.isEmpty) return (turns: const [], canPass: true, forced: pass);
    final canPass = LegalPlayGuard.canPass(deck: deck, hand: hand);

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
      if (canPass) return (turns: const [], canPass: true, forced: pass);
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

    // Partner called Tichu: never go out ahead of them (a quarter of the
    // heuristic's failed Tichus were the caller's own partner finishing
    // first). When leading, play anything but the last cards.
    if (_holdBackForPartnerTichu(snapshot, table)) {
      if (canPass &&
          legalTurns.every((turn) => turn.cards.length == hand.length)) {
        return (turns: const [], canPass: true, forced: pass);
      }
      final nonFinishing = legalTurns
          .where((turn) => turn.cards.length != hand.length)
          .toList();
      if (nonFinishing.isNotEmpty) legalTurns = nonFinishing;
    }
    return (turns: legalTurns, canPass: canPass, forced: null);
  }

  /// The actions an endgame search may choose among for this on-turn
  /// decision (the same set [selectTurn] chooses from), or null when there
  /// is nothing to search: a forced move, or a finishing move (going out is
  /// a hard rule).
  ({List<TichuTurn> turns, bool canPass})? searchableActions(
    GameSnapshot snapshot,
  ) {
    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    final turnOptions = _turnOptions(
      snapshot,
      hand,
      TableRelationships(snapshot, playerId),
    );
    if (turnOptions.forced != null) return null;
    if (turnOptions.turns.any((t) => t.cards.length == hand.length)) {
      return null;
    }
    return (turns: turnOptions.turns, canPass: turnOptions.canPass);
  }

  /// The action this agent would submit for playing [turn] (adds the wish
  /// when the Mah Jong is played). Used by training rollouts to try every
  /// legal turn.
  PlayTurnAction playActionFor(GameSnapshot snapshot, TichuTurn turn) {
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
      // Always hand off a mutable copy so downstream turn parsing can sort.
      cards: List<Card>.from(turn.cards),
      inputWish: wish,
    );
  }

  // ---------------------------------------------------------------------------
  // Wish selection
  // ---------------------------------------------------------------------------

  @override
  int selectDragonGive(GameSnapshot snapshot) =>
      dragonGiveStrategy.selectDragonGive(snapshot, playerId);

  CardFace _selectMahjongWish(
    GameSnapshot snapshot,
    List<Card> hand,
    DeckState deck,
  ) {
    final preferredWish = _lastSchupfedNextFace;

    return wishStrategy.selectWish(
      snapshot,
      hand,
      deck,
      preferredFace: preferredWish,
    );
  }

  void _syncRound(GameSnapshot snapshot) {
    if (_lastSchupfRoundNumber != snapshot.scoreState.roundNumber) {
      _lastSchupfRoundNumber = snapshot.scoreState.roundNumber;
      _lastSchupfedNextFace = null;
    }
  }
}
