import 'dart:async';

import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/record/game_record.dart';
import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/game/record/round_log.dart';
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
  GameRecord? recordFor(String gameId) => _records[gameId];

  /// Emits the record of [gameId] each time an event is added.
  Stream<GameRecord> watchRecord(String gameId) =>
      _controllerFor(gameId).stream;

  /// Completes once every pending save of [gameId] has finished.
  Future<void> flush(String gameId) =>
      _saves[gameId]?.idle ?? Future<void>.value();

  StreamController<GameRecord> _controllerFor(String gameId) =>
      _controllers.putIfAbsent(gameId, StreamController<GameRecord>.broadcast);

  @override
  GameEngineState createGame({
    required String gameId,
    required List<GamePlayer> players,
    int targetScore = 1000,
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
  void startGame(GameEngineState state) {
    _inner.startGame(state);
    _recordDeal(state);
  }

  @override
  void startNewRound(GameEngineState state) {
    _inner.startNewRound(state);
    _recordDeal(state);
  }

  @override
  void applyAction(GameEngineState state, GameAction action) {
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
    GameEngineState state, {
    String? pendingOpponentPlayerId,
    List<Card>? pendingOpponentCards,
    bool pendingOpponentPass = false,
    bool opponentAwaitingConfirmation = false,
  }) => _inner.buildSnapshot(
    state,
    pendingOpponentPlayerId: pendingOpponentPlayerId,
    pendingOpponentCards: pendingOpponentCards,
    pendingOpponentPass: pendingOpponentPass,
    opponentAwaitingConfirmation: opponentAwaitingConfirmation,
  );

  @override
  PlayerSnapshot buildPlayerSnapshot(GameSnapshot snapshot, String playerId) =>
      _inner.buildPlayerSnapshot(snapshot, playerId);

  @override
  bool hasPendingHumanSchupfReceipts(GameEngineState state) =>
      _inner.hasPendingHumanSchupfReceipts(state);

  @override
  bool shouldPauseForAutomatedOpponent(GameEngineState state, String actorId) =>
      _inner.shouldPauseForAutomatedOpponent(state, actorId);

  @override
  List<String> opponentIds(GameEngineState state, String playerId) =>
      _inner.opponentIds(state, playerId);

  // ── Recording ───────────────────────────────────────────────────────

  void _recordDeal(GameEngineState state) {
    final record = _records[state.gameId];
    if (record == null) return;
    final round = state.scoreTracker.state.roundNumber;
    record.roundsPlayed = round;
    final log = RoundLog(round: round);
    for (final p in state.players) {
      final seat = _seatOf(record, p.id);
      log.firstCards[seat].addAll(state.hands[p.id] ?? const <Card>[]);
      if (state.phase != GamePhase.grandTichu) {
        log.fullHands[seat].addAll(state.hands[p.id] ?? const <Card>[]);
      }
    }
    record.roundLogs.add(log);
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
    GameRecord record,
    GameEngineState state,
    GameAction action,
    _Before before,
  ) {
    final round = before.round;
    final who = record.nameOf(action.playerId);
    final hand = before.actorHand;
    final seat = _seatOf(record, action.playerId);
    final log = record.roundLogs.isNotEmpty ? record.roundLogs.last : null;

    switch (action) {
      case GrandTichuDecisionAction(:final call):
        if (call) log?.addGrandTichu(seat);
        record.add(
          round: round,
          kind: 'grandTichu',
          playerId: action.playerId,
          text: call ? '$who calls GRAND TICHU' : '$who: no Grand Tichu',
          data: {'call': call, 'hand': cardLabels(hand)},
        );
      case CallGrandTichuAction():
        log?.addGrandTichu(seat);
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
          if (before.phase == GamePhase.play) {
            log?.addTichuDuringPlay(seat);
          } else {
            log?.addCall(seat, grand: false);
          }
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
        log?.addSchupf(
          seat,
          selection.toLeft,
          selection.toPartner,
          selection.toRight,
        );
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
        // The engine's copy of the play carries the Phoenix's value.
        final played = turn != null && turn.cards.length == cards.length
            ? turn.cards
            : cards;
        log?.addPlay(
          seat,
          played,
          wish: inputWish,
          outOfTurn: before.currentSeat != seat,
        );
        final lead = before.onTableBy == null;
        final hasMahJong = cards.any((c) => c.face == CardFace.mahJong);
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
        final partner = record.playerAtSeat((seat + 2) % 4);
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
        log?.addPass(seat);
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
        log?.addDragonGift(
          seat,
          toLeft: _seatOf(record, targetPlayerId) == (seat + 1) % 4,
        );
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
    GameRecord record,
    GameEngineState state,
    _Before before,
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

    if (before.phase != state.phase &&
        state.phase == GamePhase.schupf &&
        record.roundLogs.isNotEmpty) {
      final log = record.roundLogs.last;
      for (final p in state.players) {
        final seat = _seatOf(record, p.id);
        log.fullHands[seat]
          ..clear()
          ..addAll(state.hands[p.id] ?? const <Card>[]);
      }
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
      if (record.roundLogs.isNotEmpty) {
        record.roundLogs.last
          ..teamOnePoints = score.teamOneRound
          ..teamTwoPoints = score.teamTwoRound;
      }
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
  Future<void> forget(String gameId) async {
    await flush(gameId);
    _records.remove(gameId);
    _saves.remove(gameId);
    await _controllers.remove(gameId)?.close();
  }

  void _changed(String gameId) {
    final record = _records[gameId];
    if (record == null) return;
    // The controllers are closed in [forget].
    if (_controllers[gameId] case final controller? when !controller.isClosed) {
      controller.add(record);
    }
    final store = this.store;
    if (store != null) {
      _saves
          .putIfAbsent(gameId, _SaveQueue.new)
          .schedule(
            () => store.save(record),
            (error) => onSaved?.call(gameId, error),
          );
    }
  }

  static int _seatOf(GameRecord record, String playerId) {
    for (final p in record.players) {
      if (p.id == playerId) return p.seat;
    }
    return 0;
  }

  static Map<String, List<String>> _hands(GameEngineState state) => {
    for (final p in state.players)
      p.id: cardLabels(state.hands[p.id] ?? const <Card>[]),
  };
}

String _typeLabel(TurnType? type) => switch (type) {
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

String _ordinal(int n) => switch (n) {
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
    required this.currentSeat,
  });

  factory _Before.capture(GameEngineState state, String actorId) {
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
      currentSeat: state.players[state.currentPlayerIndex].seat,
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

  /// Seat whose turn it was (a bomb by another seat is out of turn).
  final int currentSeat;

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
    Future<void> Function() save,
    void Function(Object? error) done,
  ) {
    if (_queued) return;
    _queued = true;
    _tail = _tail.then((_) async {
      _queued = false;
      Object? failure;
      try {
        await save();
        // A failing store must never break the game.
      } on Object catch (error) {
        failure = error;
      }
      done(failure);
    });
  }
}
