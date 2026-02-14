import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:tichu/game/game_backend.dart';
import 'package:tichu/services/local/local_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';

const _defaultTargetScore = 1000;

Future<void> main(List<String> args) async {
  final config = _parseArgs(args);
  if (config.showHelp) {
    _printUsage();
    return;
  }

  final outputFile = File(config.outputPath);
  final outputSink = outputFile.openWrite();

  final random = config.seed == null ? Random() : Random(config.seed);
  final backend = LocalGameBackend(random: random);
  await backend.setAutomatedActionDelay(Duration.zero);
  final players = _buildAutomatedPlayers();
  final gameId = await backend.createGame(
    players,
    targetScore: config.targetScore,
  );

  final stream = backend.watchGameState(gameId);
  final runner = _HeadlessRunner(
    backend: backend,
    gameId: gameId,
    stream: stream,
    output: outputSink,
    maxRounds: config.rounds,
  );

  final runFuture = runner.run();
  await backend.startGame(gameId);
  await runFuture;
  await backend.disposeGame(gameId);
  await outputSink.flush();
  await outputSink.close();
}

class _HeadlessRunner {
  final LocalGameBackend backend;
  final String gameId;
  final Stream<GameSnapshot> stream;
  final IOSink output;
  final int? maxRounds;

  GameSnapshot? _previous;
  var _sequence = 0;
  var _headerWritten = false;
  var _completedRounds = 0;
  late final StreamSubscription<GameSnapshot> _subscription;
  final Completer<void> _done = Completer<void>();

  _HeadlessRunner({
    required this.backend,
    required this.gameId,
    required this.stream,
    required this.output,
    required this.maxRounds,
  });

  Future<void> run() async {
    _subscription = stream.listen(
      (snapshot) => _handleSnapshot(snapshot),
      onError: (Object error, StackTrace stackTrace) {
        stderr.writeln('error,$error');
        if (!_done.isCompleted) {
          _done.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!_done.isCompleted) {
          _done.complete();
        }
      },
    );

    await _done.future;
    await _subscription.cancel();
  }

  void _handleSnapshot(GameSnapshot snapshot) {
    if (!_headerWritten) {
      _writeHeader();
      _headerWritten = true;
    }

    if (_previous == null) {
      _emitGameStart(snapshot);
      _emitRoundStart(snapshot);
      _previous = snapshot;
      _maybeConfirmOpponentTurn(snapshot);
      return;
    }

    _emitGrandTichuDecisions(snapshot, _previous!);
    _emitSchupfReceipts(snapshot, _previous!);
    _emitPendingOpponentAction(snapshot, _previous!);
    _emitTurnResolution(snapshot, _previous!);
    _emitDragonGive(snapshot, _previous!);
    _emitRoundEnd(snapshot, _previous!);
    _emitGameEnd(snapshot, _previous!);

    _previous = snapshot;
    _maybeConfirmOpponentTurn(snapshot);
  }

  void _emitGameStart(GameSnapshot snapshot) {
    final players = snapshot.players
        .map((p) => '${p.id}:${p.seat}:${p.type.name}')
        .join('|');
    _writeRow(event: 'game_start', snapshot: snapshot, note: players);
  }

  void _emitRoundStart(GameSnapshot snapshot) {
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

  void _emitGrandTichuDecisions(GameSnapshot snapshot, GameSnapshot previous) {
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

  void _emitSchupfReceipts(GameSnapshot snapshot, GameSnapshot previous) {
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

  void _emitPendingOpponentAction(
    GameSnapshot snapshot,
    GameSnapshot previous,
  ) {
    if (!snapshot.opponentAwaitingConfirmation ||
        snapshot.pendingOpponentPlayerId == null) {
      return;
    }
    if (previous.opponentAwaitingConfirmation &&
        previous.pendingOpponentPlayerId == snapshot.pendingOpponentPlayerId &&
        _cardsEqual(
          previous.pendingOpponentCards,
          snapshot.pendingOpponentCards,
        ) &&
        previous.pendingOpponentPass == snapshot.pendingOpponentPass) {
      return;
    }

    _writeRow(
      event: 'opponent_action',
      snapshot: snapshot,
      playerId: snapshot.pendingOpponentPlayerId,
      action: snapshot.pendingOpponentPass ? 'pass' : 'play',
      cards: snapshot.pendingOpponentCards,
    );
  }

  void _emitTurnResolution(GameSnapshot snapshot, GameSnapshot previous) {
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

  void _emitDragonGive(GameSnapshot snapshot, GameSnapshot previous) {
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

  void _emitRoundEnd(GameSnapshot snapshot, GameSnapshot previous) {
    if (!snapshot.scoreState.roundComplete ||
        previous.scoreState.roundComplete) {
      return;
    }

    _completedRounds++;

    _writeRow(
      event: 'round_end',
      snapshot: snapshot,
      note: snapshot.scoreState.finishOrder.join('|'),
    );

    if (maxRounds != null && _completedRounds >= maxRounds!) {
      if (!_done.isCompleted) {
        _done.complete();
      }
      return;
    }

    if (!snapshot.scoreState.gameComplete) {
      unawaited(backend.startNewRound(gameId));
    }
  }

  void _emitGameEnd(GameSnapshot snapshot, GameSnapshot previous) {
    if (!snapshot.scoreState.gameComplete || previous.scoreState.gameComplete) {
      return;
    }

    _writeRow(
      event: 'game_end',
      snapshot: snapshot,
      note: snapshot.scoreState.winningTeam?.toString() ?? '',
    );

    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  void _maybeConfirmOpponentTurn(GameSnapshot snapshot) {
    if (!snapshot.opponentAwaitingConfirmation) {
      return;
    }
    if (snapshot.pendingOpponentPlayerId == null) {
      return;
    }

    backend.submitAction(
      gameId,
      ConfirmOpponentTurnAction(playerId: snapshot.pendingOpponentPlayerId!),
    );
  }

  void _writeHeader() {
    output.writeln(
      'seq,ts_ms,game_id,round,phase,event,player_id,action,cards,deck_type,deck_value,active_wish,trick_points,team_one_round,team_two_round,team_one_total,team_two_total,round_complete,game_complete,note',
    );
  }

  void _writeRow({
    required String event,
    required GameSnapshot snapshot,
    String? playerId,
    String? action,
    List<Card>? cards,
    String? note,
  }) {
    final row = [
      (_sequence++).toString(),
      DateTime.now().millisecondsSinceEpoch.toString(),
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

  String _formatCards(List<Card>? cards) {
    if (cards == null || cards.isEmpty) {
      return '';
    }
    return cards.map(_cardToken).join('|');
  }

  String _cardToken(Card card) {
    if (card.face == CardFace.phoenix) {
      return 'phoenix:${card.value.toStringAsFixed(1)}';
    }
    return '${card.face.name}-${card.color.name}';
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      final escaped = value.replaceAll('"', '""');
      return '"$escaped"';
    }
    return value;
  }

  bool _cardsEqual(List<Card> a, List<Card> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _HeadlessConfig {
  final int? seed;
  final int targetScore;
  final int? rounds;
  final String outputPath;
  final bool showHelp;

  const _HeadlessConfig({
    required this.seed,
    required this.targetScore,
    required this.rounds,
    required this.outputPath,
    required this.showHelp,
  });
}

_HeadlessConfig _parseArgs(List<String> args) {
  int? seed;
  var targetScore = _defaultTargetScore;
  int? rounds;
  var outputPath = 'game.csv';
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
    if (arg.startsWith('--output=')) {
      outputPath = arg.split('=').last;
      continue;
    }
  }

  return _HeadlessConfig(
    seed: seed,
    targetScore: targetScore,
    rounds: rounds,
    outputPath: outputPath,
    showHelp: showHelp,
  );
}

void _printUsage() {
  stdout.writeln('Headless Tichu automated-opponent runner');
  stdout.writeln('Usage: dart run lib/headless/headless.dart [--seed=N]');
  stdout.writeln('       [--target-score=N] [--rounds=N] [--output=game.csv]');
}

List<GamePlayer> _buildAutomatedPlayers() {
  return const [
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
}
