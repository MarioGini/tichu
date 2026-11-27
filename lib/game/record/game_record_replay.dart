import 'package:tichu/game/agent_decisions.dart';
import 'package:tichu/game/card_identifiers.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_exceptions.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/record/round_log.dart';
import 'package:tichu/game/turn/tichu_data.dart';

final Map<int, Card> _cardsByIndex = {
  for (final c in cardIdentifiers.values) cardIndex(c): c,
};

/// Replays a stored game (format 3: one [RoundLog] string per round in
/// [rounds]) in [engine] and returns the engine state.
///
/// [players] are the record's players (any order; their seats count).
/// With [before], the replay stops just before that action, numbered from
/// 1 over all rounds as `tool/game_record.dart` prints them (`#208`): the
/// state is the decision the player of that action faced. Without it the
/// whole record is replayed.
///
/// Grand Tichu decisions of players that did not call, and schupf
/// receipts, are not in the log; they are answered here. Throws
/// [IllegalActionException] when the log does not fit the engine's rules
/// and [FormatException] when it is malformed.
GameEngineState replayGameRecord({
  required GameEngine engine,
  required List<GamePlayer> players,
  required List<String> rounds,
  String gameId = 'replay',
  int targetScore = 1000,
  int? before,
}) {
  final bySeat = [...players]..sort((a, b) => a.seat.compareTo(b.seat));
  final names = [for (final p in bySeat) p.name];
  final state = engine.createGame(
    gameId: gameId,
    players: bySeat,
    targetScore: targetScore,
  );
  engine.startGame(state);
  var seq = 0;
  for (var r = 0; r < rounds.length; r++) {
    if (r > 0) engine.startNewRound(state);
    final dealt = dealtHands(rounds[r]);
    for (var seat = 0; seat < 4; seat++) {
      final cards = [for (final i in dealt[seat]) _cardsByIndex[i]!];
      state.hands[bySeat[seat].id] = cards.sublist(0, 8);
      state.reservedHands[bySeat[seat].id] = cards.sublist(8);
    }
    final steps = replayRoundLog(rounds[r], names);
    final grand = {
      for (final s in steps)
        if (s.kind == RoundLogKind.grandTichu) bySeat[s.seat].id,
    };
    for (final step in steps) {
      seq++;
      if (seq == before) return state;
      if (step.kind == RoundLogKind.grandTichu) continue;
      _answerUnlogged(engine, state, grand);
      engine.applyAction(state, _action(step, bySeat));
    }
  }
  return state;
}

/// Answers the pending decisions the log does not hold: Grand Tichu
/// decisions (a call for the players in [grand]) and schupf receipts.
void _answerUnlogged(
  GameEngine engine,
  GameEngineState state,
  Set<String> grand,
) {
  while (true) {
    switch (AgentDecisions.next(engine, state)) {
      case GrandTichuRequest(:final playerId):
        engine.applyAction(
          state,
          GrandTichuDecisionAction(
            playerId: playerId,
            call: grand.contains(playerId),
          ),
        );
      case SchupfReceiptRequest(:final playerId):
        engine.applyAction(
          state,
          AcknowledgeSchupfAction(playerId: playerId),
        );
      default:
        return;
    }
  }
}

GameAction _action(RoundLogStep step, List<GamePlayer> bySeat) {
  final id = bySeat[step.seat].id;
  Card card(int i) => _cardsByIndex[i]!;
  return switch (step.kind) {
    RoundLogKind.grandTichu => CallGrandTichuAction(playerId: id),
    RoundLogKind.tichu => CallTichuAction(playerId: id),
    RoundLogKind.schupf => SchupfAction(
      playerId: id,
      toLeft: card(step.cards[0]),
      toPartner: card(step.cards[1]),
      toRight: card(step.cards[2]),
    ),
    RoundLogKind.pass => PassAction(playerId: id),
    RoundLogKind.dragonGift => GiveDragonAction(
      playerId: id,
      targetPlayerId: bySeat[step.target!].id,
    ),
    RoundLogKind.play => PlayTurnAction(
      playerId: id,
      cards: [
        for (final i in step.cards)
          switch ((card(i).face, step.phoenixAs)) {
            (CardFace.phoenix, final CardFace rank) => Card.phoenix(
              Card.getValue(rank),
            ),
            _ => card(i),
          },
      ],
      inputWish: step.wish,
    ),
  };
}
