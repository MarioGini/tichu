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
        (options.planScore
            ? const DefaultPlaySelectionStrategy(
                turnScorer: TurnScorer(
                  weights: PolicyWeights(planEfficiency: 2.5),
                ),
              )
            : const DefaultPlaySelectionStrategy());
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

  /// Plan-play moves decided by the situation (see [PlanPlay]).
  GameAction? _planPlay(
    final GameSnapshot snapshot,
    final DeckState deck,
    final List<Card> hand,
    final TableRelationships table,
    final List<TichuTurn> legalTurns, {
    required final bool isLeading,
  }) {
    // A partner who called and is winning the trick: never overtake.
    final partnerId = table.partnerId;
    final winnerId = deck.currentWinner.isNotEmpty
        ? deck.currentWinner
        : snapshot.lastPlayedBy;
    if (!isLeading &&
        partnerId != null &&
        winnerId == partnerId &&
        (snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none) !=
            TichuCall.none &&
        LegalPlayGuard.canPass(deck: deck, hand: hand)) {
      return PassAction(playerId: playerId);
    }
    if (!isLeading) return null;
    final lead = PlanPlay.lead(
      snapshot: snapshot,
      playerId: playerId,
      plays: legalTurns,
      hand: hand,
      table: table,
      opponentOneCard: options.planLead || options.leadOpponentOneCard,
      feedPartner: options.planLead || options.feedPartner,
      sureFirst: options.planLead || options.sureFirst,
    );
    return lead == null ? null : _buildPlayAction(snapshot, lead, deck, hand);
  }

  static int _cardsOf(final GameSnapshot snapshot, final String? id) =>
      id == null ? 0 : (snapshot.hands[id] ?? const <Card>[]).length;

  TichuTurn? _bombForValuableTrick(
    final GameSnapshot snapshot,
    final DeckState deck,
    final List<TichuTurn> plays,
    final TableRelationships table,
  ) {
    if (deck.turn.type == TurnType.empty || deck.turn.type == TurnType.none) {
      return null;
    }
    final winnerId = deck.currentWinner.isNotEmpty
        ? deck.currentWinner
        : snapshot.lastPlayedBy;
    if (winnerId == null || !table.isOpponent(winnerId)) return null;
    // (Bombing an opponent's Dragon gains nothing: a Dragon trick is given
    // to us anyway.)
    if (snapshot.trickPoints < 25) return null;
    final bombs = plays.where((final t) => t.type == TurnType.bomb).toList()
      ..sort((final a, final b) => a.value.compareTo(b.value));
    return bombs.isEmpty ? null : bombs.first;
  }

  bool _holdBackForPartnerTichu(
    final GameSnapshot snapshot,
    final TableRelationships table,
  ) {
    if (!options.supportPartnerTichu && !options.guardPartnerTichu) {
      return false;
    }
    final partnerId = table.partnerId;
    if (partnerId == null) return false;
    final partnerCall =
        snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none;
    if (partnerCall == TichuCall.none) return false;
    if (snapshot.scoreState.finishOrder.isNotEmpty) return false;
    return (snapshot.hands[partnerId] ?? const <Card>[]).isNotEmpty;
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
      final recovered = LegalPlayGuard.firstLegalTurnBruteForce(
        deck: deck,
        hand: hand,
      );
      if (recovered != null) {
        legalTurns = [recovered];
      }
    }

    if (legalTurns.isEmpty) {
      if (LegalPlayGuard.canPass(deck: deck, hand: hand)) {
        return PassAction(playerId: playerId);
      }
      throw StateError('No legal turn and pass is illegal for current state.');
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
    if (partnerPass != null && LegalPlayGuard.canPass(deck: deck, hand: hand)) {
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

    final anyLeadRule =
        options.planLead ||
        options.leadOpponentOneCard ||
        options.feedPartner ||
        options.sureFirst;
    if (anyLeadRule) {
      final planned = _planPlay(
        snapshot,
        deck,
        hand,
        table,
        legalTurns,
        isLeading: isLeading,
      );
      if (planned != null) return planned;
    }
    if (options.planLead || options.noDogAfterPartnerOut) {
      // Never lead the Dog once the partner is out (it hands the lead to an
      // opponent).
      if (isLeading && _cardsOf(snapshot, table.partnerId) == 0) {
        final noDog = legalTurns
            .where((final t) => t.type != TurnType.dog)
            .toList();
        if (noDog.isNotEmpty) legalTurns = noDog;
      }
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
    validPlays = LegalPlayGuard.strictLegalTurnsFromCandidates(
      deck: deck,
      hand: hand,
      candidates: validPlays,
    );

    validPlays = _filterLowSinglePhoenixResponses(deck, validPlays);

    if (options.planBombs) {
      validPlays = PlanPlay.keepBombs(
        snapshot: snapshot,
        plays: validPlays,
        hand: hand,
        table: table,
        deck: deck,
      );
    }
    if (options.planPass) {
      final winnerId = deck.currentWinner.isNotEmpty
          ? deck.currentWinner
          : snapshot.lastPlayedBy;
      if (!isLeading &&
          winnerId != null &&
          table.isOpponent(winnerId) &&
          LegalPlayGuard.canPass(deck: deck, hand: hand) &&
          PlanPlay.passInsteadOfDamaging(
            snapshot: snapshot,
            playerId: playerId,
            plays: validPlays,
            hand: hand,
            table: table,
          )) {
        return PassAction(playerId: playerId);
      }
    }
    if (options.conserveControls &&
        !isLeading &&
        LegalPlayGuard.canPass(deck: deck, hand: hand)) {
      final winnerId = deck.currentWinner.isNotEmpty
          ? deck.currentWinner
          : snapshot.lastPlayedBy;
      if (winnerId != null && table.isOpponent(winnerId)) {
        // Empty result = pass (handled below).
        validPlays = PlanPlay.conserveControls(
          snapshot: snapshot,
          playerId: playerId,
          plays: validPlays,
          hand: hand,
          table: table,
          deck: deck,
        );
      }
    }

    if (validPlays.isEmpty) {
      if (LegalPlayGuard.canPass(deck: deck, hand: hand)) {
        return PassAction(playerId: playerId);
      }
      final selected = playSelectionStrategy.selectPlay(
        snapshot,
        legalTurns,
        deck,
        hand,
      );
      return _buildPlayAction(snapshot, selected, deck, hand);
    }

    // Bomb a valuable trick (25+ points) an opponent is winning.
    final valuableBomb = _bombForValuableTrick(
      snapshot,
      deck,
      validPlays,
      table,
    );
    if (valuableBomb != null) {
      return _buildPlayAction(snapshot, valuableBomb, deck, hand);
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
        legalTurns: options.planSingles
            ? PlanPlay.cleanSingles(validPlays, hand)
            : validPlays,
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
      // Always hand off a mutable copy so downstream turn parsing can sort.
      cards: List<Card>.from(turn.cards),
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
