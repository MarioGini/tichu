part of 'smart_ai_agent.dart';

/// Heuristic play rules of [SmartAiAgent] (bypassed by a [FullTurnPolicy]).
extension _HeuristicTurn on SmartAiAgent {
  /// Heuristic play for a non-finishing position: tactical shortcuts first,
  /// then [playSelectionStrategy] (TurnScorer) and the cheapest equivalent
  /// combination.
  GameAction _heuristicTurn(
    final GameSnapshot snapshot,
    final DeckState deck,
    final List<Card> hand,
    final TableRelationships table,
    final List<TichuTurn> legal,
  ) {
    final legalTurns = legal;
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
    if (options.on('partner_pass') &&
        partnerPass != null &&
        LegalPlayGuard.canPass(deck: deck, hand: hand)) {
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
    if (options.on('mahjong_lead') && mahjongLead != null) {
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
    if (options.on('partner_finish_lead') && partnerLead != null) {
      return _buildPlayAction(snapshot, partnerLead, deck, hand);
    }

    final earlyDog = playTacticsPolicy.selectEarlyDogLead(
      legalTurns: legalTurns,
      isLeading: isLeading,
    );
    if (options.on('early_dog') && earlyDog != null) {
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

    final opponentThreatWinning = playTacticsPolicy
        .opponentTichuNearFinishWinning(
          playerId: playerId,
          snapshot: snapshot,
          deck: deck,
          table: table,
        );
    if (options.on('singleton_response') && !opponentThreatWinning) {
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
    return _buildPlayAction(
      snapshot,
      options.on('cheap_combos')
          ? _cheapestEquivalent(selected, validPlays)
          : selected,
      deck,
      hand,
    );
  }
}
