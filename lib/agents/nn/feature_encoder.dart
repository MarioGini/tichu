import 'package:tichu/agents/table_relationships.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Fixed-size numeric feature vector for neural network input.
///
/// Encodes game state as a dense float vector for MLP consumption.
/// All features are normalized to roughly [-1, 1] or [0, 1] ranges.
///
/// **State features** (38 floats) — indices 0-37
/// **Hand structure features** (8 floats) — indices 38-45
///   38: pair_count / 7
///   39: triplet_count / 4
///   40: straight_count / 4
///   41: fullHouse_count / 4
///   42: pairStraight_count / 4
///   43: bomb_count / 2
///   44: max_combo_size / 14
///   45: singleton_fraction (cards not in any multi-card combo / hand_size)
/// **Opponent features** (6 floats) — indices 46-51
///   46-48: opponent hand sizes / 14 (sorted ascending)
///   49: partner_called_tichu (0/1)
///   50: any_opponent_called_tichu (0/1)
///   51: any_opponent_called_grand (0/1)
/// **Action features** (12 floats) — indices 52-63
///   52-57: action type one-hot (single, pair, triple, straight, bomb, pass)
///   58: action_value / 25
///   59: action_card_count / 14
///   60: is_phoenix_play (0/1)
///   61: is_dragon_play (0/1)
///   62: is_dog_play (0/1)
///   63: relative_strength (action_value - deck_value) / 25, clamped ±1

const stateFeatureCount = 46;
const opponentFeatureCount = 6;
const stateAndOpponentFeatureCount = stateFeatureCount + opponentFeatureCount;
const actionFeatureCount = 12;
const totalFeatureCount = stateAndOpponentFeatureCount + actionFeatureCount;

/// Encode the game state for [playerId] into a fixed-size float vector.
List<double> encodeStateFeatures({
  required final GameSnapshot snapshot,
  required final String playerId,
}) {
  final features = List<double>.filled(stateAndOpponentFeatureCount, 0.0);

  final player = snapshot.players.firstWhere(
    (final p) => p.id == playerId,
    orElse: () => snapshot.players.first,
  );
  final team = player.seat.isEven ? 0 : 1;
  final hand = snapshot.hands[playerId] ?? const <Card>[];
  final table = TableRelationships(snapshot, playerId);

  // Basic identity.
  features[0] = team.toDouble();
  features[1] = snapshot.currentPlayerId == playerId ? 1.0 : 0.0;

  // Phase one-hot.
  switch (snapshot.phase) {
    case GamePhase.grandTichu:
      features[2] = 1.0;
    case GamePhase.schupf:
      features[3] = 1.0;
    case GamePhase.play:
      features[4] = 1.0;
  }

  // Hand composition.
  features[5] = hand.length / 14.0;
  var lowCount = 0;
  var midCount = 0;
  var highCount = 0;
  var specialCount = 0;
  var hasMahJong = false;
  var hasPhoenix = false;
  var hasDragon = false;
  var hasDog = false;

  for (final card in hand) {
    switch (card.face) {
      case CardFace.mahJong:
        hasMahJong = true;
        specialCount++;
      case CardFace.phoenix:
        hasPhoenix = true;
        specialCount++;
      case CardFace.dragon:
        hasDragon = true;
        specialCount++;
      case CardFace.dog:
        hasDog = true;
        specialCount++;
      case CardFace.two ||
          CardFace.three ||
          CardFace.four ||
          CardFace.five ||
          CardFace.six:
        lowCount++;
      case CardFace.seven ||
          CardFace.eight ||
          CardFace.nine ||
          CardFace.ten:
        midCount++;
      case CardFace.jack ||
          CardFace.queen ||
          CardFace.king ||
          CardFace.ace:
        highCount++;
      case CardFace.none:
    }
  }

  features[6] = lowCount / 14.0;
  features[7] = midCount / 14.0;
  features[8] = highCount / 14.0;
  features[9] = specialCount / 4.0;
  features[10] = hasMahJong ? 1.0 : 0.0;
  features[11] = hasPhoenix ? 1.0 : 0.0;
  features[12] = hasDragon ? 1.0 : 0.0;
  features[13] = hasDog ? 1.0 : 0.0;
  features[14] = (snapshot.hasBombByPlayer[playerId] ?? false) ? 1.0 : 0.0;
  features[15] = (snapshot.canBombByPlayer[playerId] ?? false) ? 1.0 : 0.0;
  features[16] =
      (snapshot.canCallTichuByPlayer[playerId] ?? false) ? 1.0 : 0.0;

  // Deck state.
  final deckType = snapshot.deck.turn.type;
  if (deckType == TurnType.empty || deckType == TurnType.none) {
    features[17] = 1.0; // empty
  } else if (deckType == TurnType.bomb) {
    features[19] = 1.0; // bomb
  } else {
    features[18] = 1.0; // normal trick
  }
  features[20] = snapshot.deck.turn.value / 25.0;
  features[21] = snapshot.deck.turn.cards.length / 14.0;

  // Trick winner relation.
  final winner = snapshot.deck.currentWinner;
  if (winner == playerId) {
    features[22] = 1.0;
  } else if (winner.isNotEmpty && table.isPartner(winner)) {
    features[23] = 1.0;
  } else if (winner.isNotEmpty) {
    features[24] = 1.0;
  }

  // Wish.
  final wish = snapshot.activeWish;
  if (wish != CardFace.none) {
    features[25] = _faceValue(wish) / 14.0;
    features[26] =
        hand.any((final c) => c.face == wish) ? 1.0 : 0.0;
  }

  features[27] = snapshot.consecutivePasses / 3.0;
  features[28] = snapshot.scoreState.finishOrder.length / 4.0;

  // Score gap.
  final ownScore = _teamScore(snapshot.scoreState, team);
  final oppScore = _teamScore(snapshot.scoreState, team == 0 ? 1 : 0);
  features[29] = ((ownScore - oppScore) / 500.0).clamp(-1.0, 1.0);

  // Own tichu call.
  final ownCall =
      snapshot.scoreState.tichuCalls[playerId] ?? TichuCall.none;
  if (ownCall == TichuCall.tichu) {
    features[30] = 1.0;
  } else if (ownCall == TichuCall.grandTichu) {
    features[31] = 1.0;
  }

  // Hand structure features — what combos can the hand actually form?
  // This is the critical signal the NN needs to prefer multi-card plays.
  if (hand.length >= 2) {
    final emptyDeck = DeckState(
      TichuTurn(TurnType.empty, const []),
      CardFace.none,
    );
    final allTurns = generateLegalTurns(emptyDeck, List<Card>.from(hand));

    var pairCount = 0;
    var tripletCount = 0;
    var straightCount = 0;
    var fullHouseCount = 0;
    var pairStraightCount = 0;
    var bombCount = 0;
    var maxComboSize = 1;

    for (final turn in allTurns) {
      switch (turn.type) {
        case TurnType.pair:
          pairCount++;
        case TurnType.triplet:
          tripletCount++;
        case TurnType.straight:
          straightCount++;
        case TurnType.fullHouse:
          fullHouseCount++;
        case TurnType.pairStraight:
          pairStraightCount++;
        case TurnType.bomb:
          bombCount++;
        case TurnType.single || TurnType.dog || TurnType.none ||
             TurnType.empty:
          break;
      }
      if (turn.cards.length > maxComboSize) {
        maxComboSize = turn.cards.length;
      }
    }

    features[32] = pairCount / 7.0;
    features[33] = tripletCount / 4.0;
    features[34] = straightCount / 4.0;
    features[35] = fullHouseCount / 4.0;
    features[36] = pairStraightCount / 4.0;
    features[37] = bombCount / 2.0;
    features[38] = maxComboSize / 14.0;

    // Estimate singleton fraction: how many cards aren't in multi-card combos.
    final multiCardCount = pairCount * 2 +
        tripletCount * 3 +
        straightCount * 5 +
        fullHouseCount * 5 +
        pairStraightCount * 4;
    final est = (multiCardCount / hand.length).clamp(0.0, 1.0);
    features[39] = 1.0 - est; // singleton fraction (lower = better structure)
  } else {
    features[39] = 1.0; // only singletons
  }

  // Opponent info (indices 40-45).
  final oppCounts = <double>[];
  for (final p in snapshot.players) {
    if (p.id != playerId) {
      oppCounts.add((snapshot.hands[p.id]?.length ?? 0) / 14.0);
    }
  }
  oppCounts.sort();
  for (var i = 0; i < oppCounts.length && i < 3; i++) {
    features[40 + i] = oppCounts[i];
  }

  // Partner/opponent call state.
  final partnerId = table.partnerId ?? '';
  final partnerCall =
      snapshot.scoreState.tichuCalls[partnerId] ?? TichuCall.none;
  features[43] = partnerCall != TichuCall.none ? 1.0 : 0.0;

  var anyOppTichu = false;
  var anyOppGrand = false;
  for (final opp in table.opponents) {
    final oppCall =
        snapshot.scoreState.tichuCalls[opp.id] ?? TichuCall.none;
    if (oppCall == TichuCall.tichu) anyOppTichu = true;
    if (oppCall == TichuCall.grandTichu) anyOppGrand = true;
  }
  features[44] = anyOppTichu ? 1.0 : 0.0;
  features[45] = anyOppGrand ? 1.0 : 0.0;

  return features;
}

/// Encode a play action (or pass) into a fixed-size float vector.
List<double> encodeActionFeatures({
  required final TichuTurn play,
  required final DeckState deck,
  required final bool isPass,
}) {
  final features = List<double>.filled(actionFeatureCount, 0.0);

  if (isPass) {
    features[5] = 1.0; // pass slot
    return features;
  }

  // Action type one-hot.
  switch (play.type) {
    case TurnType.single:
      features[0] = 1.0;
    case TurnType.pair:
      features[0] = 0.5;
      features[1] = 1.0;
    case TurnType.triplet:
      features[2] = 1.0;
    case TurnType.straight || TurnType.pairStraight || TurnType.fullHouse:
      features[3] = 1.0;
    case TurnType.bomb:
      features[4] = 1.0;
    case TurnType.none || TurnType.empty || TurnType.dog:
      break;
  }

  features[6] = play.value / 25.0;
  features[7] = play.cards.length / 14.0;

  // Special card flags.
  for (final card in play.cards) {
    if (card.face == CardFace.phoenix) features[8] = 1.0;
    if (card.face == CardFace.dragon) features[9] = 1.0;
    if (card.face == CardFace.dog) features[10] = 1.0;
  }

  // Relative strength vs deck.
  final deckValue = deck.turn.value;
  features[11] = ((play.value - deckValue) / 25.0).clamp(-1.0, 1.0);

  return features;
}

/// Combine state + action features into a single input vector.
List<double> encodeStateActionFeatures({
  required final GameSnapshot snapshot,
  required final String playerId,
  required final TichuTurn play,
  required final DeckState deck,
  final bool isPass = false,
}) {
  final state = encodeStateFeatures(snapshot: snapshot, playerId: playerId);
  final action = encodeActionFeatures(
    play: play,
    deck: deck,
    isPass: isPass,
  );
  return [...state, ...action];
}

double _faceValue(final CardFace face) {
  switch (face) {
    case CardFace.two:
      return 2;
    case CardFace.three:
      return 3;
    case CardFace.four:
      return 4;
    case CardFace.five:
      return 5;
    case CardFace.six:
      return 6;
    case CardFace.seven:
      return 7;
    case CardFace.eight:
      return 8;
    case CardFace.nine:
      return 9;
    case CardFace.ten:
      return 10;
    case CardFace.jack:
      return 11;
    case CardFace.queen:
      return 12;
    case CardFace.king:
      return 13;
    case CardFace.ace:
      return 14;
    case CardFace.mahJong || CardFace.phoenix || CardFace.dragon ||
         CardFace.dog || CardFace.none:
      return 0;
  }
}

int _teamScore(final ScoreState scoreState, final int team) {
  if (team == 0) {
    return scoreState.teamOneTotal + scoreState.teamOneRound;
  }
  return scoreState.teamTwoTotal + scoreState.teamTwoRound;
}
