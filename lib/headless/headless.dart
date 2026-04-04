import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tichu/agents/rl_codec.dart';
import 'package:tichu/agents/rl_policy_play_selection_strategy.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/engine.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/engine/engine_impl.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/wish_logic.dart';

const _defaultTargetScore = 1000;
const _defaultEpisodes = 1;
const _defaultMaxStepsPerEpisode = 200000;

Future<void> main(final List<String> args) async {
  final config = _parseArgs(args);
  if (config.showHelp) {
    _printUsage();
    return;
  }

  final outputSink = config.outputFormat == _HeadlessOutputFormat.none
      ? null
      : File(config.outputPath).openWrite();

  final rlPolicy = await _loadRlPolicy(config.rlPolicyPath);
  final agentFactory = _buildAgentFactory(rlPolicy: rlPolicy);

  final random = config.seed == null ? Random() : Random(config.seed);

  final simulator = _HeadlessSimulator(
    random: random,
    targetScore: config.targetScore,
    roundsLimit: config.rounds,
    episodes: config.episodes,
    maxStepsPerEpisode: config.maxStepsPerEpisode,
    outputFormat: config.outputFormat,
    output: outputSink,
    includeTimestamps: config.includeTimestamps,
    includeLegalTurnCount: config.includeLegalTurnCount,
    agentFactory: agentFactory,
  );

  try {
    await simulator.run();
  } finally {
    if (outputSink != null) {
      await outputSink.flush();
      await outputSink.close();
    }
  }
}

class _HeadlessSimulator {
  final Random random;
  final int targetScore;
  final int? roundsLimit;
  final int episodes;
  final int maxStepsPerEpisode;
  final _HeadlessOutputFormat outputFormat;
  final IOSink? output;
  final bool includeTimestamps;
  final bool includeLegalTurnCount;
  final PlayerAgent Function(String playerId) agentFactory;

  _HeadlessSimulator({
    required this.random,
    required this.targetScore,
    required this.roundsLimit,
    required this.episodes,
    required this.maxStepsPerEpisode,
    required this.outputFormat,
    required this.output,
    required this.includeTimestamps,
    required this.includeLegalTurnCount,
    required this.agentFactory,
  });

  Future<void> run() async {
    for (var episode = 0; episode < episodes; episode++) {
      await _runEpisode(episode + 1);
    }
  }

  Future<void> _runEpisode(final int episodeNumber) async {
    final players = _buildAutomatedPlayers();
    final agents = {
      for (final player in players) player.id: agentFactory(player.id),
    };
    final engine = GameEngineImpl(random: random);
    final state = engine.createGame(
      gameId: 'headless_episode_$episodeNumber',
      players: players,
      targetScore: targetScore,
    );
    engine.startGame(state);

    final csvWriter =
        outputFormat == _HeadlessOutputFormat.csv && output != null
        ? _CsvEventWriter(output: output!, includeTimestamps: includeTimestamps)
        : null;
    final rlWriter =
        outputFormat == _HeadlessOutputFormat.rlJsonl && output != null
        ? _RlTransitionWriter(
            output: output!,
            episode: episodeNumber,
            includeLegalTurnCount: includeLegalTurnCount,
          )
        : null;

    var snapshot = engine.buildSnapshot(state);
    csvWriter?.processSnapshot(snapshot);

    var completedRounds = 0;
    var steps = 0;

    while (true) {
      if (snapshot.scoreState.gameComplete) {
        return;
      }
      if (roundsLimit != null && completedRounds >= roundsLimit!) {
        return;
      }

      if (snapshot.scoreState.roundComplete) {
        engine.startNewRound(state);
        snapshot = engine.buildSnapshot(state);
        csvWriter?.processSnapshot(snapshot);
        continue;
      }

      if (steps >= maxStepsPerEpisode) {
        throw StateError(
          'Episode $episodeNumber exceeded max steps ($maxStepsPerEpisode).',
        );
      }

      final action = await _selectAction(
        engine: engine,
        state: state,
        snapshot: snapshot,
        agents: agents,
      );

      final before = snapshot;
      final appliedAction = _applyActionWithRecovery(
        engine: engine,
        state: state,
        snapshot: snapshot,
        selectedAction: action,
      );
      steps++;

      if (appliedAction is PlayTurnAction || appliedAction is PassAction) {
        csvWriter?.emitOpponentAction(snapshot: before, action: appliedAction);
      }

      snapshot = engine.buildSnapshot(state);
      csvWriter?.processSnapshot(snapshot);
      rlWriter?.emitTransition(
        before: before,
        action: appliedAction,
        after: snapshot,
        step: steps,
      );

      if (!before.scoreState.roundComplete &&
          snapshot.scoreState.roundComplete) {
        completedRounds++;
      }
    }
  }

  Future<GameAction> _selectAction({
    required final GameEngine engine,
    required final GameEngineState state,
    required final GameSnapshot snapshot,
    required final Map<String, PlayerAgent> agents,
  }) async {
    final receiptPlayerId = _nextReceiptPlayerId(state);
    if (receiptPlayerId != null) {
      return AcknowledgeSchupfAction(playerId: receiptPlayerId);
    }

    if (state.phase == GamePhase.grandTichu) {
      final currentPlayer = state.players[state.currentPlayerIndex];
      if (state.grandTichuDecisions.containsKey(currentPlayer.id)) {
        state.currentPlayerIndex =
            (state.currentPlayerIndex + 1) % state.players.length;
        return _selectAction(
          engine: engine,
          state: state,
          snapshot: snapshot,
          agents: agents,
        );
      }

      final agent = agents[currentPlayer.id];
      if (agent == null) {
        throw StateError('No agent registered for ${currentPlayer.id}.');
      }

      final shouldCall = await agent.shouldCallGrandTichu(snapshot);
      return GrandTichuDecisionAction(
        playerId: currentPlayer.id,
        call: shouldCall,
      );
    }

    if (state.phase == GamePhase.schupf) {
      for (final player in state.players) {
        if (state.schupfSelections.containsKey(player.id)) {
          continue;
        }

        final agent = agents[player.id];
        if (agent == null) {
          throw StateError('No agent registered for ${player.id}.');
        }
        return agent.selectSchupfCards(snapshot);
      }

      throw StateError('Schupf phase active but no player can schupfen.');
    }

    if (state.pendingDragonGiveBy != null) {
      final winnerId = state.pendingDragonGiveBy!;
      final opponentIds = engine.opponentIds(state, winnerId);
      if (opponentIds.isEmpty) {
        throw StateError('No valid dragon target available for $winnerId.');
      }

      final preferredSeat = agents[winnerId]?.selectDragonGive(snapshot);
      final targetId = _resolveDragonTarget(
        state: state,
        opponentIds: opponentIds,
        preferredSeat: preferredSeat,
      );

      return GiveDragonAction(playerId: winnerId, targetPlayerId: targetId);
    }

    final currentPlayer = state.players[state.currentPlayerIndex];
    final agent = agents[currentPlayer.id];
    if (agent == null) {
      throw StateError('No agent registered for ${currentPlayer.id}.');
    }
    return agent.selectAction(snapshot);
  }

  GameAction _applyActionWithRecovery({
    required final GameEngine engine,
    required final GameEngineState state,
    required final GameSnapshot snapshot,
    required final GameAction selectedAction,
  }) {
    final normalizedSelectedAction = _normalizeActionForEngine(selectedAction);

    _assertActionLegal(snapshot: snapshot, action: normalizedSelectedAction);
    engine.applyAction(state, normalizedSelectedAction);
    return normalizedSelectedAction;
  }

  GameAction _normalizeActionForEngine(final GameAction action) {
    if (action is PlayTurnAction) {
      return PlayTurnAction(
        playerId: action.playerId,
        cards: List<Card>.from(action.cards),
        inputWish: action.inputWish,
      );
    }
    return action;
  }

  void _assertActionLegal({
    required final GameSnapshot snapshot,
    required final GameAction action,
  }) {
    if (action is PlayTurnAction) {
      _assertPlayActionLegal(snapshot: snapshot, action: action);
      return;
    }

    if (action is PassAction) {
      _assertPassActionLegal(snapshot: snapshot, action: action);
    }
  }

  void _assertPlayActionLegal({
    required final GameSnapshot snapshot,
    required final PlayTurnAction action,
  }) {
    if (snapshot.phase != GamePhase.play) {
      throw StateError('Illegal play action outside play phase.');
    }
    if (action.playerId != snapshot.currentPlayerId) {
      throw StateError('Illegal play action by non-current player.');
    }

    final hand = List<Card>.from(
      snapshot.hands[action.playerId] ?? const <Card>[],
    );
    if (!_handContainsAllCards(hand: hand, cards: action.cards)) {
      throw StateError('Illegal play action: cards not in hand.');
    }

    late final TichuTurn turn;
    try {
      turn = getTurn(List<Card>.from(action.cards));
    } on Exception {
      throw StateError('Illegal play action: invalid turn shape.');
    }
    if (turn.type == TurnType.none) {
      throw StateError('Illegal play action: invalid turn shape.');
    }
    if (mahJong(snapshot.deck, turn, hand)) {
      throw StateError('Illegal play action: wish must be fulfilled.');
    }
    if (!validTurn(snapshot.deck.turn, turn)) {
      throw StateError('Illegal play action: does not beat current deck turn.');
    }
  }

  void _assertPassActionLegal({
    required final GameSnapshot snapshot,
    required final PassAction action,
  }) {
    if (snapshot.phase != GamePhase.play) {
      throw StateError('Illegal pass action outside play phase.');
    }
    if (action.playerId != snapshot.currentPlayerId) {
      throw StateError('Illegal pass action by non-current player.');
    }

    final hand = List<Card>.from(
      snapshot.hands[action.playerId] ?? const <Card>[],
    );
    if (!_canPass(snapshot: snapshot, hand: hand)) {
      throw StateError('Illegal pass action for current deck/hand state.');
    }
  }

  bool _handContainsAllCards({
    required final List<Card> hand,
    required final List<Card> cards,
  }) {
    final temp = List<Card>.from(hand);
    for (final card in cards) {
      final index = temp.indexWhere((final candidate) {
        if (card.face == CardFace.phoenix) {
          return candidate.face == CardFace.phoenix;
        }
        return candidate.face == card.face && candidate.color == card.color;
      });
      if (index < 0) {
        return false;
      }
      temp.removeAt(index);
    }
    return true;
  }

  bool _canPass({
    required final GameSnapshot snapshot,
    required final List<Card> hand,
  }) {
    if (snapshot.deck.turn.type == TurnType.empty ||
        snapshot.deck.turn.type == TurnType.none) {
      return false;
    }
    return !mahJong(snapshot.deck, TichuTurn(TurnType.none, const []), hand);
  }

  String? _nextReceiptPlayerId(final GameEngineState state) {
    for (final player in state.players) {
      final receipts = state.schupfReceipts[player.id];
      if (receipts != null && receipts.isNotEmpty) {
        return player.id;
      }
    }
    return null;
  }

  String _resolveDragonTarget({
    required final GameEngineState state,
    required final List<String> opponentIds,
    required final int? preferredSeat,
  }) {
    if (preferredSeat != null) {
      for (final player in state.players) {
        if (player.seat == preferredSeat && opponentIds.contains(player.id)) {
          return player.id;
        }
      }
    }
    return opponentIds.first;
  }
}

class _CsvEventWriter {
  final IOSink output;
  final bool includeTimestamps;

  GameSnapshot? _previous;
  var _sequence = 0;
  var _headerWritten = false;

  _CsvEventWriter({required this.output, required this.includeTimestamps});

  void processSnapshot(final GameSnapshot snapshot) {
    if (!_headerWritten) {
      _writeHeader();
      _headerWritten = true;
    }

    if (_previous == null) {
      _emitGameStart(snapshot);
      _emitRoundStart(snapshot);
      _previous = snapshot;
      return;
    }

    _emitGrandTichuDecisions(snapshot, _previous!);
    _emitSchupfReceipts(snapshot, _previous!);
    _emitTurnResolution(snapshot, _previous!);
    _emitDragonGive(snapshot, _previous!);
    _emitRoundEnd(snapshot, _previous!);
    _emitGameEnd(snapshot, _previous!);

    _previous = snapshot;
  }

  void emitOpponentAction({
    required final GameSnapshot snapshot,
    required final GameAction action,
  }) {
    if (action is PlayTurnAction) {
      _writeRow(
        event: 'opponent_action',
        snapshot: snapshot,
        playerId: action.playerId,
        action: 'play',
        cards: action.cards,
      );
      return;
    }

    if (action is PassAction) {
      _writeRow(
        event: 'opponent_action',
        snapshot: snapshot,
        playerId: action.playerId,
        action: 'pass',
      );
    }
  }

  void _emitGameStart(final GameSnapshot snapshot) {
    final players = snapshot.players
        .map((final p) => '${p.id}:${p.seat}:${p.type.name}')
        .join('|');
    _writeRow(event: 'game_start', snapshot: snapshot, note: players);
  }

  void _emitRoundStart(final GameSnapshot snapshot) {
    _writeRow(event: 'round_start', snapshot: snapshot);
    for (final entry in snapshot.hands.entries) {
      _writeRow(
        event: 'initial_hand',
        snapshot: snapshot,
        playerId: entry.key,
        cards: entry.value,
      );
    }
  }

  void _emitGrandTichuDecisions(
    final GameSnapshot snapshot,
    final GameSnapshot previous,
  ) {
    for (final entry in snapshot.grandTichuDecisions.entries) {
      if (previous.grandTichuDecisions.containsKey(entry.key)) {
        continue;
      }
      _writeRow(
        event: 'grand_tichu',
        snapshot: snapshot,
        playerId: entry.key,
        action: entry.value ? 'call' : 'pass',
      );
    }

    if (previous.scoreState.roundNumber != snapshot.scoreState.roundNumber) {
      _emitRoundStart(snapshot);
    }
  }

  void _emitSchupfReceipts(
    final GameSnapshot snapshot,
    final GameSnapshot previous,
  ) {
    if (previous.phase == GamePhase.schupf &&
        snapshot.phase == GamePhase.play) {
      for (final entry in snapshot.schupfReceipts.entries) {
        final recipientId = entry.key;
        for (final receipt in entry.value) {
          _writeRow(
            event: 'schupf_receipt',
            snapshot: snapshot,
            playerId: recipientId,
            action: receipt.direction.name,
            cards: [receipt.card],
            note: receipt.fromPlayerId,
          );
        }
      }
    }
  }

  void _emitTurnResolution(
    final GameSnapshot snapshot,
    final GameSnapshot previous,
  ) {
    if (snapshot.lastPlayedTurn == null) {
      return;
    }
    if (previous.lastPlayedTurn == snapshot.lastPlayedTurn &&
        previous.lastPlayedBy == snapshot.lastPlayedBy) {
      return;
    }

    _writeRow(
      event: 'turn_resolved',
      snapshot: snapshot,
      playerId: snapshot.lastPlayedBy,
      action: snapshot.lastPlayedTurn!.type.name,
      cards: snapshot.lastPlayedTurn!.cards,
    );
  }

  void _emitDragonGive(
    final GameSnapshot snapshot,
    final GameSnapshot previous,
  ) {
    if (snapshot.lastDragonGiveBy == null ||
        snapshot.lastDragonGiveTo == null) {
      return;
    }
    if (snapshot.lastDragonGiveBy == previous.lastDragonGiveBy &&
        snapshot.lastDragonGiveTo == previous.lastDragonGiveTo) {
      return;
    }

    _writeRow(
      event: 'dragon_give',
      snapshot: snapshot,
      playerId: snapshot.lastDragonGiveBy,
      action: snapshot.lastDragonGiveTo,
    );
  }

  void _emitRoundEnd(final GameSnapshot snapshot, final GameSnapshot previous) {
    if (!snapshot.scoreState.roundComplete ||
        previous.scoreState.roundComplete) {
      return;
    }

    _writeRow(
      event: 'round_end',
      snapshot: snapshot,
      note: snapshot.scoreState.finishOrder.join('|'),
    );
  }

  void _emitGameEnd(final GameSnapshot snapshot, final GameSnapshot previous) {
    if (!snapshot.scoreState.gameComplete || previous.scoreState.gameComplete) {
      return;
    }

    _writeRow(
      event: 'game_end',
      snapshot: snapshot,
      note: snapshot.scoreState.winningTeam?.toString() ?? '',
    );
  }

  void _writeHeader() {
    output.writeln(
      'seq,ts_ms,game_id,round,phase,event,player_id,action,cards,deck_type,deck_value,active_wish,trick_points,team_one_round,team_two_round,team_one_total,team_two_total,round_complete,game_complete,note',
    );
  }

  void _writeRow({
    required final String event,
    required final GameSnapshot snapshot,
    final String? playerId,
    final String? action,
    final List<Card>? cards,
    final String? note,
  }) {
    final sequence = _sequence++;
    final ts = includeTimestamps ? DateTime.now().millisecondsSinceEpoch : 0;
    final row = [
      sequence.toString(),
      ts.toString(),
      snapshot.gameId,
      snapshot.scoreState.roundNumber.toString(),
      snapshot.phase.name,
      event,
      playerId ?? '',
      action ?? '',
      _formatCards(cards),
      snapshot.deck.turn.type.name,
      snapshot.deck.turn.value.toStringAsFixed(1),
      snapshot.activeWish.name,
      snapshot.trickPoints.toString(),
      snapshot.scoreState.teamOneRound.toString(),
      snapshot.scoreState.teamTwoRound.toString(),
      snapshot.scoreState.teamOneTotal.toString(),
      snapshot.scoreState.teamTwoTotal.toString(),
      snapshot.scoreState.roundComplete.toString(),
      snapshot.scoreState.gameComplete.toString(),
      note ?? '',
    ];

    output.writeln(row.map(_csvEscape).join(','));
  }

  String _csvEscape(final String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      final escaped = value.replaceAll('"', '""');
      return '"$escaped"';
    }
    return value;
  }

  String _formatCards(final List<Card>? cards) {
    if (cards == null || cards.isEmpty) {
      return '';
    }
    return cards.map(_cardToken).join('|');
  }
}

class _RlTransitionWriter {
  final IOSink output;
  final int episode;
  final bool includeLegalTurnCount;

  var _sequence = 0;

  _RlTransitionWriter({
    required this.output,
    required this.episode,
    required this.includeLegalTurnCount,
  });

  void emitTransition({
    required final GameSnapshot before,
    required final GameAction action,
    required final GameSnapshot after,
    required final int step,
  }) {
    final actorTeam = _teamForPlayer(before, action.playerId);
    final reward = _rewardDelta(
      actorTeam: actorTeam,
      before: before.scoreState,
      after: after.scoreState,
    );
    final actionKey = encodeRlActionKey(action);
    final actionShapeKey = encodeRlActionShapeKey(action);
    final stateKey = buildRlStateKey(
      snapshot: before,
      playerId: action.playerId,
    );
    final stateKeyCoarse = buildRlCoarseStateKey(
      snapshot: before,
      playerId: action.playerId,
    );
    final nextStateKey = buildRlStateKey(
      snapshot: after,
      playerId: action.playerId,
    );
    final nextStateKeyCoarse = buildRlCoarseStateKey(
      snapshot: after,
      playerId: action.playerId,
    );
    final stateObs = buildRlObservation(
      snapshot: before,
      playerId: action.playerId,
    );
    final nextStateObs = buildRlObservation(
      snapshot: after,
      playerId: action.playerId,
    );
    final legalActionKeys = _legalActionKeys(before, action.playerId);
    final actionIndex = legalActionKeys?.indexOf(actionKey);

    final legalTurnCount = includeLegalTurnCount
        ? _computeLegalTurnCount(before, action.playerId)
        : null;

    final record = <String, Object?>{
      'schema_version': rlTransitionSchemaVersion,
      'episode': episode,
      'seq': _sequence++,
      'step': step,
      'state_key': stateKey,
      'state_key_coarse': stateKeyCoarse,
      'next_state_key': nextStateKey,
      'next_state_key_coarse': nextStateKeyCoarse,
      'state': stateObs,
      'next_state': nextStateObs,
      'action_key': actionKey,
      'action_shape_key': actionShapeKey,
      'action': _actionPayload(action),
      'legal_action_keys': legalActionKeys,
      'legal_actions_enumerated': legalActionKeys != null,
      'action_index': actionIndex != null && actionIndex >= 0
          ? actionIndex
          : null,
      'player_id': action.playerId,
      'team': actorTeam,
      'phase': before.phase.name,
      'action_type': _actionType(action),
      'cards': _cardsForAction(action).map(_cardToken).toList(growable: false),
      'input_wish': action is PlayTurnAction ? action.inputWish.name : null,
      'grand_tichu_call': action is GrandTichuDecisionAction
          ? action.call
          : null,
      'dragon_target': action is GiveDragonAction
          ? action.targetPlayerId
          : null,
      'reward': reward,
      'done': after.scoreState.gameComplete,
      'discount': after.scoreState.gameComplete ? 0.0 : 1.0,
      'round': after.scoreState.roundNumber,
      'team_one_round': after.scoreState.teamOneRound,
      'team_two_round': after.scoreState.teamTwoRound,
      'team_one_total': after.scoreState.teamOneTotal,
      'team_two_total': after.scoreState.teamTwoTotal,
      'current_player_id': after.currentPlayerId,
      'deck_type': after.deck.turn.type.name,
      'deck_value': after.deck.turn.value,
      'active_wish': after.activeWish.name,
      'hand_size': (after.hands[action.playerId] ?? const <Card>[]).length,
      'opponent_card_counts': _opponentCounts(after, action.playerId),
      'legal_turn_count': legalTurnCount,
    };
    record.removeWhere((final _, final value) => value == null);
    output.writeln(jsonEncode(record));
  }

  Map<String, Object?> _actionPayload(final GameAction action) {
    final payload = <String, Object?>{
      'type': _actionType(action),
      'player_id': action.playerId,
      'key': encodeRlActionKey(action),
      'shape_key': encodeRlActionShapeKey(action),
    };

    if (action is PlayTurnAction) {
      payload['cards'] = action.cards.map(_cardToken).toList(growable: false);
      payload['wish'] = action.inputWish.name;
    } else if (action is SchupfAction) {
      payload['to_left'] = _cardToken(action.toLeft);
      payload['to_partner'] = _cardToken(action.toPartner);
      payload['to_right'] = _cardToken(action.toRight);
    } else if (action is GiveDragonAction) {
      payload['target_player_id'] = action.targetPlayerId;
    } else if (action is GrandTichuDecisionAction) {
      payload['call'] = action.call;
    }

    return payload;
  }

  int _teamForPlayer(final GameSnapshot snapshot, final String playerId) {
    final player = snapshot.players.firstWhere(
      (final p) => p.id == playerId,
      orElse: () => snapshot.players.first,
    );
    return player.seat.isEven ? 0 : 1;
  }

  double _rewardDelta({
    required final int actorTeam,
    required final ScoreState before,
    required final ScoreState after,
  }) {
    final beforeActor = _teamScore(before, actorTeam);
    final beforeOpponent = _teamScore(before, actorTeam == 0 ? 1 : 0);
    final afterActor = _teamScore(after, actorTeam);
    final afterOpponent = _teamScore(after, actorTeam == 0 ? 1 : 0);
    return (afterActor - beforeActor - (afterOpponent - beforeOpponent))
        .toDouble();
  }

  int _teamScore(final ScoreState scoreState, final int team) {
    if (team == 0) {
      return scoreState.teamOneTotal + scoreState.teamOneRound;
    }
    return scoreState.teamTwoTotal + scoreState.teamTwoRound;
  }

  int _computeLegalTurnCount(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    if (snapshot.phase != GamePhase.play) {
      return 0;
    }
    final hand = snapshot.hands[playerId] ?? const <Card>[];
    return generateLegalTurns(snapshot.deck, List<Card>.from(hand)).length;
  }

  List<String>? _legalActionKeys(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    if (snapshot.currentPlayerId != playerId) {
      return null;
    }

    if (snapshot.phase == GamePhase.grandTichu) {
      return const ['grand_tichu:call', 'grand_tichu:pass'];
    }

    if (snapshot.phase == GamePhase.schupf) {
      // Schupf has a very large combinatorial action space.
      return null;
    }

    if (snapshot.phase != GamePhase.play) {
      return null;
    }

    if (snapshot.pendingDragonGiveBy == playerId) {
      final keys =
          snapshot.pendingDragonGiveTargets
              .map((final id) => 'dragon_give:$id')
              .toList()
            ..sort();
      return keys;
    }

    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    final turns = generateLegalTurns(snapshot.deck, hand);
    final keys = <String>{
      for (final turn in turns) encodeRlPlayActionKeyFromTurn(turn),
    };

    if (_canPass(snapshot, hand)) {
      keys.add('pass');
    }

    if (snapshot.canCallTichuByPlayer[playerId] ?? false) {
      keys.add('call_tichu');
    }

    final sorted = keys.toList()..sort();
    return sorted;
  }

  bool _canPass(final GameSnapshot snapshot, final List<Card> hand) {
    if (snapshot.deck.turn.type == TurnType.empty ||
        snapshot.deck.turn.type == TurnType.none) {
      return false;
    }
    return !mahJong(snapshot.deck, TichuTurn(TurnType.none, const []), hand);
  }

  Map<String, int> _opponentCounts(
    final GameSnapshot snapshot,
    final String playerId,
  ) {
    final counts = <String, int>{};
    for (final entry in snapshot.hands.entries) {
      if (entry.key == playerId) {
        continue;
      }
      counts[entry.key] = entry.value.length;
    }
    return counts;
  }

  String _actionType(final GameAction action) {
    if (action is PlayTurnAction) return 'play';
    if (action is PassAction) return 'pass';
    if (action is GiveDragonAction) return 'dragon_give';
    if (action is AcknowledgeSchupfAction) return 'ack_schupf';
    if (action is SchupfAction) return 'schupf';
    if (action is CallTichuAction) return 'tichu';
    if (action is CallGrandTichuAction) return 'grand_tichu';
    if (action is GrandTichuDecisionAction) return 'grand_tichu_decision';
    if (action is ConfirmOpponentTurnAction) return 'confirm';
    return 'unknown';
  }

  List<Card> _cardsForAction(final GameAction action) {
    if (action is PlayTurnAction) {
      return action.cards;
    }
    if (action is SchupfAction) {
      return [action.toLeft, action.toPartner, action.toRight];
    }
    return const <Card>[];
  }
}

class _HeadlessConfig {
  final int? seed;
  final int targetScore;
  final int? rounds;
  final int episodes;
  final int maxStepsPerEpisode;
  final String outputPath;
  final _HeadlessOutputFormat outputFormat;
  final bool showHelp;
  final bool includeTimestamps;
  final bool includeLegalTurnCount;
  final String? rlPolicyPath;

  const _HeadlessConfig({
    required this.seed,
    required this.targetScore,
    required this.rounds,
    required this.episodes,
    required this.maxStepsPerEpisode,
    required this.outputPath,
    required this.outputFormat,
    required this.showHelp,
    required this.includeTimestamps,
    required this.includeLegalTurnCount,
    required this.rlPolicyPath,
  });
}

enum _HeadlessOutputFormat { csv, rlJsonl, none }

_HeadlessConfig _parseArgs(final List<String> args) {
  int? seed;
  var targetScore = _defaultTargetScore;
  int? rounds;
  var outputPath = 'game.csv';
  var outputFormat = _HeadlessOutputFormat.csv;
  var episodes = _defaultEpisodes;
  var maxStepsPerEpisode = _defaultMaxStepsPerEpisode;
  var includeTimestamps = true;
  var includeLegalTurnCount = false;
  String? rlPolicyPath;
  var outputProvided = false;
  var showHelp = false;

  for (final arg in args) {
    if (arg == '--help' || arg == '-h') {
      showHelp = true;
      continue;
    }
    if (arg.startsWith('--seed=')) {
      seed = int.tryParse(arg.split('=').last);
      continue;
    }
    if (arg.startsWith('--target-score=')) {
      targetScore = int.tryParse(arg.split('=').last) ?? _defaultTargetScore;
      continue;
    }
    if (arg.startsWith('--rounds=')) {
      final parsedRounds = int.tryParse(arg.split('=').last);
      if (parsedRounds != null && parsedRounds > 0) {
        rounds = parsedRounds;
      }
      continue;
    }

    if (arg.startsWith('--episodes=')) {
      final parsedEpisodes = int.tryParse(arg.split('=').last);
      if (parsedEpisodes != null && parsedEpisodes > 0) {
        episodes = parsedEpisodes;
      }
      continue;
    }

    if (arg.startsWith('--max-steps=')) {
      final parsedMaxSteps = int.tryParse(arg.split('=').last);
      if (parsedMaxSteps != null && parsedMaxSteps > 0) {
        maxStepsPerEpisode = parsedMaxSteps;
      }
      continue;
    }

    if (arg.startsWith('--format=')) {
      final formatValue = arg.split('=').last;
      switch (formatValue) {
        case 'csv':
          outputFormat = _HeadlessOutputFormat.csv;
        case 'rl-jsonl':
          outputFormat = _HeadlessOutputFormat.rlJsonl;
        case 'none':
          outputFormat = _HeadlessOutputFormat.none;
      }
      continue;
    }

    if (arg == '--rl') {
      outputFormat = _HeadlessOutputFormat.rlJsonl;
      continue;
    }

    if (arg == '--no-timestamps') {
      includeTimestamps = false;
      continue;
    }

    if (arg == '--rl-legal-count') {
      includeLegalTurnCount = true;
      continue;
    }

    if (arg.startsWith('--rl-policy=')) {
      rlPolicyPath = arg.split('=').last;
      continue;
    }

    if (arg.startsWith('--output=')) {
      outputPath = arg.split('=').last;
      outputProvided = true;
      continue;
    }
  }

  if (!outputProvided && outputFormat == _HeadlessOutputFormat.rlJsonl) {
    outputPath = 'game.jsonl';
  }

  return _HeadlessConfig(
    seed: seed,
    targetScore: targetScore,
    rounds: rounds,
    episodes: episodes,
    maxStepsPerEpisode: maxStepsPerEpisode,
    outputPath: outputPath,
    outputFormat: outputFormat,
    showHelp: showHelp,
    includeTimestamps: includeTimestamps,
    includeLegalTurnCount: includeLegalTurnCount,
    rlPolicyPath: rlPolicyPath,
  );
}

void _printUsage() {
  stdout.writeln('Headless Tichu automated-opponent runner');
  stdout.writeln('Usage: dart run lib/headless/headless.dart [--seed=N]');
  stdout.writeln(
    '       [--target-score=N] [--rounds=N] [--episodes=N] [--max-steps=N]',
  );
  stdout.writeln(
    '       [--format=csv|rl-jsonl|none] [--output=path] [--no-timestamps]',
  );
  stdout.writeln('       [--rl-legal-count] [--rl-policy=policy.json] [--rl]');
}

List<GamePlayer> _buildAutomatedPlayers() => const [
  GamePlayer(
    id: 'auto_1',
    name: 'Opponent 1',
    seat: 0,
    type: PlayerType.automated,
  ),
  GamePlayer(
    id: 'auto_2',
    name: 'Opponent 2',
    seat: 1,
    type: PlayerType.automated,
  ),
  GamePlayer(
    id: 'auto_3',
    name: 'Opponent 3',
    seat: 2,
    type: PlayerType.automated,
  ),
  GamePlayer(
    id: 'auto_4',
    name: 'Opponent 4',
    seat: 3,
    type: PlayerType.automated,
  ),
];

String _cardToken(final Card card) {
  if (card.face == CardFace.phoenix) {
    return 'phoenix:${card.value.toStringAsFixed(1)}';
  }
  return '${card.face.name}-${card.color.name}';
}

Future<RlPolicyTable?> _loadRlPolicy(final String? path) async {
  if (path == null || path.isEmpty) {
    return null;
  }

  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('RL policy file does not exist: $path');
  }

  final jsonText = await file.readAsString();
  final decoded = jsonDecode(jsonText);
  final table = RlPolicyTable.fromJsonObject(decoded);
  if (table.isEmpty) {
    stderr.writeln('warning,rl_policy_empty,$path');
  }
  return table;
}

PlayerAgent Function(String playerId) _buildAgentFactory({
  required final RlPolicyTable? rlPolicy,
}) {
  if (rlPolicy == null || rlPolicy.isEmpty) {
    return SmartAiAgent.new;
  }

  return (final playerId) => SmartAiAgent(
    playerId,
    playSelectionStrategy: RlPolicyPlaySelectionStrategy(
      playerId: playerId,
      policy: rlPolicy,
    ),
  );
}
