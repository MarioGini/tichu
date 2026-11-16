part of 'smart_ai_agent.dart';

/// Heuristic play rules of [SmartAiAgent] (bypassed by a [FullTurnPolicy]).
extension _HeuristicTurn on SmartAiAgent {
  /// Heuristic play for a non-finishing position: tactical shortcuts first,
  /// then the hand-plan rules, then [playSelectionStrategy].
  GameAction _heuristicTurn(
    final GameSnapshot snapshot,
    final DeckState deck,
    final List<Card> hand,
    final TableRelationships table,
    final List<TichuTurn> legal,
  ) {
    var legalTurns = legal;
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
}
