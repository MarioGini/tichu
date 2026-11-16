part of 'feature_encoder.dart';

/// State-feature groups (hand, played, unseen, trick, seats, self, hand
/// structure); layout in `rl/schema/feature_spec.json`.
extension _StateEncoding on FeatureEncoder {
  List<double> _encodeState() {
    final f = List<double>.filled(stateFeatureCount, 0);

    // hand / played bitmaps.
    for (final slot in _handSlots) {
      f[handOffset + slot] = 1.0;
    }
    for (var slot = 0; slot < CardKnowledge.slotCount; slot++) {
      if (_k.isSlotPlayed(slot)) f[playedOffset + slot] = 1.0;
    }

    // unseen per rank.
    const rankFaces = [
      CardFace.two,
      CardFace.three,
      CardFace.four,
      CardFace.five,
      CardFace.six,
      CardFace.seven,
      CardFace.eight,
      CardFace.nine,
      CardFace.ten,
      CardFace.jack,
      CardFace.queen,
      CardFace.king,
      CardFace.ace,
    ];
    for (var i = 0; i < rankFaces.length; i++) {
      f[unseenOffset + i] = _k.unseenCount(rankFaces[i]) / 4.0;
    }
    f[unseenOffset + 13] = _k.unseenCount(CardFace.mahJong).toDouble();
    f[unseenOffset + 14] = _k.dogUnseen ? 1.0 : 0.0;
    f[unseenOffset + 15] = _k.phoenixUnseen ? 1.0 : 0.0;
    f[unseenOffset + 16] = _k.dragonUnseen ? 1.0 : 0.0;

    _encodeTrick(f);
    _encodeSeats(f);
    _encodeSelf(f);
    _handShape.writeTo(f, handStructureOffset);
    return f;
  }

  void _encodeTrick(final List<double> f) {
    final deck = snapshot.deck;
    final turn = deck.turn;
    const o = trickOffset;
    if (_isLead(deck)) {
      f[o + 0] = 1.0;
    } else {
      switch (turn.type) {
        case TurnType.single:
          f[o + 1] = 1.0;
        case TurnType.pair:
          f[o + 2] = 1.0;
        case TurnType.triplet:
          f[o + 3] = 1.0;
        case TurnType.fullHouse:
          f[o + 4] = 1.0;
        case TurnType.straight:
          f[o + 5] = 1.0;
        case TurnType.pairStraight:
          f[o + 6] = 1.0;
        case TurnType.bomb:
          f[o + 7] = 1.0;
        case TurnType.none || TurnType.empty || TurnType.dog:
          break;
      }
      f[o + 8] = (turn.value / 25.0).clamp(-1.0, 1.0);
      f[o + 9] = turn.cards.length / 14.0;
      f[o + 19] =
          turn.type == TurnType.single &&
              turn.cards.any((final c) => c.face == CardFace.dragon)
          ? 1.0
          : 0.0;
    }
    f[o + 10] = (snapshot.trickPoints / 50.0).clamp(-1.0, 1.0);

    final winner = deck.currentWinner;
    if (winner.isNotEmpty) {
      final rel = _relativeSeat(winner);
      if (rel >= 0) f[o + 11 + rel] = 1.0;
    }
    f[o + 15] = (snapshot.consecutivePasses / 3.0).clamp(0.0, 1.0);

    final wish = snapshot.activeWish;
    if (wish != CardFace.none) {
      f[o + 16] = 1.0;
      f[o + 17] = faceRank(wish) / 14.0;
      f[o + 18] = _hand.any((final c) => c.face == wish) ? 1.0 : 0.0;
    }
  }

  void _encodeSeats(final List<double> f) {
    final score = snapshot.scoreState;
    final finishOrder = score.finishOrder;
    for (var rel = 1; rel <= 3; rel++) {
      final o = seatsOffset + (rel - 1) * 9;
      final player = _playerAtSeat((_mySeat + rel) % 4);
      if (player == null) continue;
      final id = player.id;
      final count = snapshot.hands[id]?.length ?? 0;
      f[o + 0] = count / 14.0;
      f[o + 1] = count == 1 ? 1.0 : 0.0;
      f[o + 2] = count > 0 && count <= 3 ? 1.0 : 0.0;
      f[o + 3] = finishOrder.contains(id) ? 1.0 : 0.0;
      f[o + 4] = finishOrder.isNotEmpty && finishOrder.first == id ? 1.0 : 0.0;
      final call = score.tichuCalls[id] ?? TichuCall.none;
      f[o + 5] = call == TichuCall.tichu ? 1.0 : 0.0;
      f[o + 6] = call == TichuCall.grandTichu ? 1.0 : 0.0;
      f[o + 7] = ((score.playerRoundPoints[id] ?? 0) / 100.0).clamp(-1.0, 1.0);
      f[o + 8] = _knownPassedHeld(id) / 3.0;
    }
  }

  /// Cards I schupfed to [otherId] that have not been played yet — these are
  /// known to still be in that player's hand.
  int _knownPassedHeld(final String otherId) {
    final receipts =
        snapshot.schupfReceipts[otherId] ?? const <SchupfReceipt>[];
    var held = 0;
    for (final r in receipts) {
      if (r.fromPlayerId != playerId) continue;
      if (_k.isUnseen(r.card)) held++;
    }
    return held;
  }

  void _encodeSelf(final List<double> f) {
    const o = selfOffset;
    final score = snapshot.scoreState;
    final myCall = score.tichuCalls[playerId] ?? TichuCall.none;
    f[o + 0] = _hand.length / 14.0;
    f[o + 1] = myCall == TichuCall.tichu ? 1.0 : 0.0;
    f[o + 2] = myCall == TichuCall.grandTichu ? 1.0 : 0.0;
    f[o + 3] = (snapshot.canCallTichuByPlayer[playerId] ?? false) ? 1.0 : 0.0;
    f[o + 4] = ((score.playerRoundPoints[playerId] ?? 0) / 100.0).clamp(
      -1.0,
      1.0,
    );
    f[o + 5] = score.finishOrder.length / 4.0;
    if (score.finishOrder.isNotEmpty) {
      final first = _relativeSeat(score.finishOrder.first);
      if (first == 0 || first == 2) {
        f[o + 6] = 1.0;
      } else if (first == 1 || first == 3) {
        f[o + 7] = 1.0;
      }
    }
    f[o + 8] = _handShape.bombs > 0 ? 1.0 : 0.0;

    final myTeam = _mySeat.isEven ? 0 : 1;
    final ownRound = myTeam == 0 ? score.teamOneRound : score.teamTwoRound;
    final oppRound = myTeam == 0 ? score.teamTwoRound : score.teamOneRound;
    final ownTotal = myTeam == 0 ? score.teamOneTotal : score.teamTwoTotal;
    final oppTotal = myTeam == 0 ? score.teamTwoTotal : score.teamOneTotal;
    f[o + 9] = (ownRound / 100.0).clamp(-1.0, 1.0);
    f[o + 10] = (oppRound / 100.0).clamp(-1.0, 1.0);
    f[o + 11] = ((ownTotal + ownRound - oppTotal - oppRound) / 500.0).clamp(
      -1.0,
      1.0,
    );
    final target = score.targetScore > 0 ? score.targetScore : 1000;
    f[o + 12] = ((target - ownTotal) / target).clamp(0.0, 1.0);
    f[o + 13] = ((target - oppTotal) / target).clamp(0.0, 1.0);
    f[o + 14] = _k.unseenBombPossible ? 1.0 : 0.0;
  }
}
