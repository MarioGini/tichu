import 'dart:async';

import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/record/game_record.dart';
import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/game/scoring/score_data.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// [GameEngine] decorator that writes a [GameRecord] of every game it runs.
///
/// All decisions pass through [applyAction] (human and bot alike), so the
/// record holds each move together with the hand it was made from. The
/// record is saved to [store] after every change.
class RecordingGameEngine implements GameEngine {
  RecordingGameEngine(
    this._inner, {
    this.store,
    this.botDescription,
    this.onSaved,
  });

  /// Called after each save attempt (with the error, if it failed).
  final void Function(String gameId, Object? error)? onSaved;

  final GameEngine _inner;
  final GameRecordStore? store;
  final String? botDescription;

  final Map<String, GameRecord> _records = {};
  final Map<String, StreamController<GameRecord>> _controllers = {};
  final Map<String, _SaveQueue> _saves = {};

  /// The record of [gameId], if this engine created that game.
  GameRecord? recordFor(final String gameId) => _records[gameId];

  /// Emits the record of [gameId] each time an event is added.
  Stream<GameRecord> watchRecord(final String gameId) =>
      _controllerFor(gameId).stream;

  /// Completes once every pending save of [gameId] has finished.
  Future<void> flush(final String gameId) =>
      _saves[gameId]?.idle ?? Future<void>.value();

  StreamController<GameRecord> _controllerFor(final String gameId) =>
      _controllers.putIfAbsent(gameId, StreamController<GameRecord>.broadcast);

  @override
  GameEngineState createGame({
    required final String gameId,
    required final List<GamePlayer> players,
    final int targetScore = 1000,
  }) {
    final state = _inner.createGame(
      gameId: gameId,
      players: players,
      targetScore: targetScore,
    );
    _records[gameId] = GameRecord(
      id: gameId,
      players: List<GamePlayer>.unmodifiable(players),
      targetScore: targetScore,
      botDescription: botDescription,
    );
    _changed(gameId);
    return state;
  }

  @override
  void startGame(final GameEngineState state) {
    _inner.startGame(state);
    _recordDeal(state);
  }

  @override
  void startNewRound(final GameEngineState state) {
    _inner.startNewRound(state);
    _recordDeal(state);
  }

  @override
  void applyAction(final GameEngineState state, final GameAction action) {
    final record = _records[state.gameId];
    if (record == null) {
      _inner.applyAction(state, action);
      return;
    }
    final before = _Before.capture(state, action.playerId);
    _inner.applyAction(state, action);
    _recordAction(record, state, action, before);
    _changed(state.gameId);
  }

  @override
  GameSnapshot buildSnapshot(
    final GameEngineState state, {
    final String? pendingOpponentPlayerId,
    final List<Card>? pendingOpponentCards,
    final bool pendingOpponentPass = false,
    final bool opponentAwaitingConfirmation = false,
  }) => _inner.buildSnapshot(
    state,
    pendingOpponentPlayerId: pendingOpponentPlayerId,
    pendingOpponentCards: pendingOpponentCards,
    pendingOpponentPass: pendingOpponentPass,
    opponentAwaitingConfirmation: opponentAwaitingConfirmation,
  );

  @override
  PlayerSnapshot buildPlayerSnapshot(
    final GameSnapshot snapshot,
    final String playerId,
  ) => _inner.buildPlayerSnapshot(snapshot, playerId);

  @override
  bool hasPendingHumanSchupfReceipts(final GameEngineState state) =>
      _inner.hasPendingHumanSchupfReceipts(state);

  @override
  bool shouldPauseForAutomatedOpponent(
    final GameEngineState state,
    final String actorId,
  ) => _inner.shouldPauseForAutomatedOpponent(state, actorId);

  @override
  List<String> opponentIds(
    final GameEngineState state,
    final String playerId,
  ) => _inner.opponentIds(state, playerId);

  // ── Recording ───────────────────────────────────────────────────────

  void _recordDeal(final GameEngineState state) {
    final record = _records[state.gameId];
    if (record == null) return;
    final round = state.scoreTracker.state.roundNumber;
    record.roundsPlayed = round;
    record.add(
      round: round,
      kind: 'deal',
      text:
          'Round $round: first 8 cards dealt '
          '(score ${record.teamOneTotal}:${record.teamTwoTotal})',
      data: {'hands': _hands(state), 'phase': state.phase.name},
    );
    _changed(state.gameId);
  }

  void _recordAction(
    final GameRecord record,
    final GameEngineState state,
    final GameAction action,
    final _Before before,
  ) {
    final round = before.round;
    final who = record.nameOf(action.playerId);
    final hand = before.actorHand;

    switch (action) {
      case GrandTichuDecisionAction(:final call):
        record.add(
          round: round,
          kind: 'grandTichu',
          playerId: action.playerId,
          text: call ? '$who calls GRAND TICHU' : '$who: no Grand Tichu',
          data: {'call': call, 'hand': cardLabels(hand)},
        );
      case CallGrandTichuAction():
        record.add(
          round: round,
          kind: 'grandTichu',
          playerId: action.playerId,
          text: '$who calls GRAND TICHU',
          data: {'call': true, 'hand': cardLabels(hand)},
        );
      case CallTichuAction():
        if (before.tichuCalls[action.playerId] !=
            state.scoreTracker.state.tichuCalls[action.playerId]) {
          record.add(
            round: round,
            kind: 'tichu',
            playerId: action.playerId,
            text: before.phase == GamePhase.play
                ? '$who calls TICHU'
                : '$who calls TICHU (before the schupf)',
            data: {'phase': before.phase.name, 'hand': cardLabels(hand)},
          );
        }
      case SchupfAction():
        final selection =
            state.schupfSelections[action.playerId] ??
            state.completedSchupfSelections[action.playerId] ??
            action;
        final seat = _seatOf(record, action.playerId);
        final left = record.playerAtSeat((seat + 1) % 4);
        final partner = record.playerAtSeat((seat + 2) % 4);
        final right = record.playerAtSeat((seat + 3) % 4);
        record.add(
          round: round,
          kind: 'schupf',
          playerId: action.playerId,
          text:
              '$who passes ${cardLabel(selection.toLeft)} → ${left?.name}, '
              '${cardLabel(selection.toPartner)} → ${partner?.name} '
              '(partner), ${cardLabel(selection.toRight)} → ${right?.name}',
          data: {
            'toLeft': {'player': left?.id, 'card': cardLabel(selection.toLeft)},
            'toPartner': {
              'player': partner?.id,
              'card': cardLabel(selection.toPartner),
            },
            'toRight': {
              'player': right?.id,
              'card': cardLabel(selection.toRight),
            },
            'hand': cardLabels(hand),
          },
        );
      case PlayTurnAction(:final cards, :final inputWish):
        final turn = state.lastPlayedBy == action.playerId
            ? state.lastPlayedTurn
            : null;
        final type = turn?.type ?? before.onTableType;
        final lead = before.onTableBy == null;
        final hasMahJong = cards.any((final c) => c.face == CardFace.mahJong);
        final wish = inputWish != CardFace.none
            ? ', wishes ${faceLabel(inputWish)}'
            : hasMahJong
            ? ', no wish'
            : '';
        final over = lead
            ? 'leads'
            : "plays on ${record.nameOf(before.onTableBy)}'s "
                  '${before.onTableText}';
        final isDog = cards.length == 1 && cards.first.face == CardFace.dog;
        final partner = record.playerAtSeat(
          (_seatOf(record, action.playerId) + 2) % 4,
        );
        record.add(
          round: round,
          kind: 'play',
          playerId: action.playerId,
          text: isDog
              ? '$who plays the Dog (lead to ${partner?.name})'
              : '$who $over: ${_typeLabel(type)} '
                    '${cardLabels(cards).join(' ')}$wish',
          data: {
            'cards': cardLabels(cards),
            'type': type?.name,
            'lead': lead,
            if (!lead) 'onTable': before.onTableJson,
            if (inputWish != CardFace.none) 'wish': faceLabel(inputWish),
            if (before.wish != CardFace.none)
              'activeWish': faceLabel(before.wish),
            'hand': cardLabels(hand),
            'cardCounts': before.cardCounts,
          },
        );
      case PassAction():
        record.add(
          round: round,
          kind: 'pass',
          playerId: action.playerId,
          text:
              "$who passes on ${record.nameOf(before.onTableBy)}'s "
              '${before.onTableText}',
          data: {
            'onTable': before.onTableJson,
            if (before.wish != CardFace.none)
              'activeWish': faceLabel(before.wish),
            'hand': cardLabels(hand),
            'cardCounts': before.cardCounts,
          },
        );
      case GiveDragonAction(:final targetPlayerId):
        record.add(
          round: round,
          kind: 'dragon',
          playerId: action.playerId,
          text:
              '$who gives the Dragon trick '
              '(${before.pendingDragonPoints} pts) to '
              '${record.nameOf(targetPlayerId)}',
          data: {
            'to': targetPlayerId,
            'points': before.pendingDragonPoints,
            'cardCounts': before.cardCounts,
          },
        );
      default:
        // Acknowledgements and confirmations change nothing worth keeping.
        break;
    }

    _recordConsequences(record, state, before);
  }

  /// Trick won, player out, phase changes and the round result.
  void _recordConsequences(
    final GameRecord record,
    final GameEngineState state,
    final _Before before,
  ) {
    final round = before.round;

    if (before.trickCards.isNotEmpty &&
        state.currentTrickCards.isEmpty &&
        before.onTableBy != null &&
        state.pendingDragonGiveBy == null &&
        before.pendingDragonGiveBy == null) {
      final points = pointsForCards(before.trickCards);
      record.add(
        round: round,
        kind: 'trick',
        playerId: before.onTableBy,
        text: '${record.nameOf(before.onTableBy)} wins the trick ($points pts)',
        data: {'points': points, 'cards': cardLabels(before.trickCards)},
      );
    } else if (state.pendingDragonGiveBy != null &&
        before.pendingDragonGiveBy == null) {
      record.add(
        round: round,
        kind: 'trick',
        playerId: state.pendingDragonGiveBy,
        text:
            '${record.nameOf(state.pendingDragonGiveBy)} wins the trick '
            'with the Dragon and must give it away',
        data: {'points': pointsForCards(state.pendingDragonTrickCards)},
      );
    }

    final finishOrder = state.scoreTracker.state.finishOrder;
    for (final playerId in finishOrder) {
      if (before.finishOrder.contains(playerId)) continue;
      final place = finishOrder.indexOf(playerId) + 1;
      record.add(
        round: round,
        kind: 'out',
        playerId: playerId,
        text: place == state.players.length
            ? '${record.nameOf(playerId)} is last'
            : '${record.nameOf(playerId)} is out (${_ordinal(place)})',
        data: {'place': place},
      );
    }

    if (before.phase != state.phase) {
      final label = switch (state.phase) {
        GamePhase.schupf => 'Full hands (14 cards), before the schupf',
        GamePhase.play => 'Hands after the schupf',
        GamePhase.grandTichu => 'New deal',
      };
      record.add(
        round: round,
        kind: 'hands',
        text: label,
        data: {'phase': state.phase.name, 'hands': _hands(state)},
      );
    }

    final score = state.scoreTracker.state;
    if (!before.roundComplete && score.roundComplete) {
      record
        ..teamOneTotal = score.teamOneTotal
        ..teamTwoTotal = score.teamTwoTotal;
      final last = score.rounds.isNotEmpty ? score.rounds.last : null;
      final calls = <String, String>{
        for (final e in score.tichuCalls.entries)
          if (e.value != TichuCall.none) e.key: e.value.name,
      };
      final callText = calls.isEmpty
          ? ''
          : ' — calls: ${[for (final e in calls.entries) '${record.nameOf(e.key)} ${e.value}${score.finishOrder.isNotEmpty && score.finishOrder.first == e.key ? ' ✓' : ' ✗'}'].join(', ')}';
      record.add(
        round: round,
        kind: 'roundEnd',
        text:
            'Round $round over: ${score.teamOneRound}:${score.teamTwoRound} '
            '(total ${score.teamOneTotal}:${score.teamTwoTotal})'
            '${last?.isMatch ?? false ? ' — double win' : ''}$callText',
        data: {
          'teamOneRound': score.teamOneRound,
          'teamTwoRound': score.teamTwoRound,
          'teamOneTotal': score.teamOneTotal,
          'teamTwoTotal': score.teamTwoTotal,
          'finishOrder': score.finishOrder,
          'tichuCalls': calls,
          if (last != null) ...{
            'teamOneCardPoints': last.teamOneCardPoints,
            'teamTwoCardPoints': last.teamTwoCardPoints,
            'teamOneBonusPoints': last.teamOneBonusPoints,
            'teamTwoBonusPoints': last.teamTwoBonusPoints,
            'doubleWin': last.isMatch,
          },
          'handsLeft': {
            for (final e in state.hands.entries)
              if (e.value.isNotEmpty) e.key: cardLabels(e.value),
          },
        },
      );
      if (score.gameComplete) {
        record
          ..complete = true
          ..winningTeam = score.winningTeam;
        record.add(
          round: round,
          kind: 'gameEnd',
          text:
              'Game over: ${score.teamOneTotal}:${score.teamTwoTotal}, '
              '${score.winningTeam == 0 ? 'team one' : 'team two'} wins',
          data: {'winningTeam': score.winningTeam},
        );
      }
    }
  }

  /// Stops [watchRecord] streams of [gameId] and drops the in-memory record
  /// (the stored copy is kept).
  Future<void> forget(final String gameId) async {
    await flush(gameId);
    _records.remove(gameId);
    _saves.remove(gameId);
    await _controllers.remove(gameId)?.close();
  }

  void _changed(final String gameId) {
    final record = _records[gameId];
    if (record == null) return;
    // Closed in [forget].
    // ignore: close_sinks
    final controller = _controllers[gameId];
    if (controller != null && !controller.isClosed) controller.add(record);
    final store = this.store;
    if (store != null) {
      _saves
          .putIfAbsent(gameId, _SaveQueue.new)
          .schedule(
            () => store.save(record),
            (final error) => onSaved?.call(gameId, error),
          );
    }
  }

  static int _seatOf(final GameRecord record, final String playerId) {
    for (final p in record.players) {
      if (p.id == playerId) return p.seat;
    }
    return 0;
  }

  static Map<String, List<String>> _hands(final GameEngineState state) => {
    for (final p in state.players)
      p.id: cardLabels(state.hands[p.id] ?? const <Card>[]),
  };
}

String _typeLabel(final TurnType? type) => switch (type) {
  TurnType.single => 'single',
  TurnType.pair => 'pair',
  TurnType.pairStraight => 'pair straight',
  TurnType.triplet => 'triplet',
  TurnType.fullHouse => 'full house',
  TurnType.straight => 'straight',
  TurnType.dog => 'Dog',
  TurnType.bomb => 'BOMB',
  _ => '',
};

String _ordinal(final int n) => switch (n) {
  1 => '1st',
  2 => '2nd',
  3 => '3rd',
  _ => '${n}th',
};

/// State captured right before an action is applied.
class _Before {
  _Before({
    required this.round,
    required this.phase,
    required this.actorHand,
    required this.onTableBy,
    required this.onTableType,
    required this.onTableCards,
    required this.trickCards,
    required this.wish,
    required this.finishOrder,
    required this.roundComplete,
    required this.tichuCalls,
    required this.cardCounts,
    required this.pendingDragonGiveBy,
    required this.pendingDragonPoints,
  });

  factory _Before.capture(final GameEngineState state, final String actorId) {
    final score = state.scoreTracker.state;
    final turn = state.lastPlayedTurn;
    final hasTable =
        state.lastPlayedBy != null &&
        turn != null &&
        turn.cards.isNotEmpty &&
        state.currentTrickCards.isNotEmpty;
    return _Before(
      round: score.roundNumber,
      phase: state.phase,
      actorHand: List<Card>.from(state.hands[actorId] ?? const <Card>[]),
      onTableBy: hasTable ? state.lastPlayedBy : null,
      onTableType: hasTable ? turn.type : null,
      onTableCards: hasTable ? List<Card>.from(turn.cards) : const <Card>[],
      trickCards: List<Card>.from(state.currentTrickCards),
      wish: state.deck.wish,
      finishOrder: List<String>.from(score.finishOrder),
      roundComplete: score.roundComplete,
      tichuCalls: Map<String, TichuCall>.from(score.tichuCalls),
      cardCounts: {
        for (final p in state.players) p.id: state.hands[p.id]?.length ?? 0,
      },
      pendingDragonGiveBy: state.pendingDragonGiveBy,
      pendingDragonPoints: pointsForCards(state.pendingDragonTrickCards),
    );
  }

  final int round;
  final GamePhase phase;
  final List<Card> actorHand;
  final String? onTableBy;
  final TurnType? onTableType;
  final List<Card> onTableCards;
  final List<Card> trickCards;
  final CardFace wish;
  final List<String> finishOrder;
  final bool roundComplete;
  final Map<String, TichuCall> tichuCalls;
  final Map<String, int> cardCounts;
  final String? pendingDragonGiveBy;
  final int pendingDragonPoints;

  String get onTableText =>
      '${_typeLabel(onTableType)} ${cardLabels(onTableCards).join(' ')}';

  Map<String, Object?> get onTableJson => {
    'by': onTableBy,
    'type': onTableType?.name,
    'cards': cardLabels(onTableCards),
  };
}

/// Runs saves one after another, coalescing saves requested meanwhile.
class _SaveQueue {
  Future<void> _tail = Future<void>.value();
  bool _queued = false;

  Future<void> get idle => _tail;

  void schedule(
    final Future<void> Function() save,
    final void Function(Object? error) done,
  ) {
    if (_queued) return;
    _queued = true;
    _tail = _tail.then((_) async {
      _queued = false;
      Object? failure;
      try {
        await save();
        // A failing store must never break the game.
        // ignore: avoid_catches_without_on_clauses
      } catch (error) {
        failure = error;
      }
      done(failure);
    });
  }
}
