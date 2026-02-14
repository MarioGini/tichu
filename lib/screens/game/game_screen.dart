import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:tichu/game/game_play_controller.dart';
import 'package:tichu/game/turn_rules_adapter.dart';
import 'package:tichu/game/player_control.dart';

import '../../game/game_backend.dart';
import '../../services/local/local_backend.dart';
import '../../services/sound_effects.dart';
import '../../game/scoring/score_tracker.dart';
import '../../game/turn/tichu_data.dart';
import '../../widgets/action_bar.dart';
import '../../widgets/card_widget.dart';
import '../../widgets/hand_display.dart';
import '../../widgets/opponent_display.dart';
import '../../widgets/overlapping_card_row.dart';
import '../../widgets/trick_display.dart';
import 'widgets/bomb_slam_overlay.dart';
import 'widgets/game_board.dart';

part 'parts/game_screen_actions.dart';
part 'parts/game_screen_state_bindings.dart';
part 'parts/game_screen_dialogs.dart';
part 'parts/game_screen_logic.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    GameBackend? backend,
    int targetScore = 1000,
    this.playerControlModes = const {},
  })
    : _backend = backend,
      _targetScore = targetScore;

  final GameBackend? _backend;
  final int _targetScore;
  final Map<String, PlayerControlMode> playerControlModes;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with
        SingleTickerProviderStateMixin,
        _GameScreenBindings,
        _GameScreenActions,
        _GameScreenHelpers,
        _GameScreenDialogs {
  @override
  final String _humanId = 'player-0';
  final Map<String, PlayerControlMode> _resolvedPlayerControls = {};
  PlayerControlMode _selfControlMode = PlayerControlMode.manual;

  @override
  bool get _isSelfManual => _selfControlMode == PlayerControlMode.manual;
  @override
  late final GameBackend _backend;
  @override
  final TurnRulesAdapter _turnRules = TurnRulesAdapter();
  @override
  late final GamePlayController _playController = GamePlayController(
    turnRules: _turnRules,
  );
  late final List<GamePlayer> _players;
  StreamSubscription<PlayerSnapshot>? _subscription;
  @override
  PlayerSnapshot? _snapshot;

  @override
  List<Card> _hand = [];
  @override
  final Set<int> _selectedIndexes = <int>{};
  List<Card> _trickCards = <Card>[];
  List<Card> _pendingOpponentCards = <Card>[];
  bool _pendingOpponentPass = false;
  String? _pendingOpponentLabel;
  String? _dragonGiveKey;
  TichuTurn? _dragonGiveTurn;
  @override
  String? _gameId;
  @override
  int _lastDialogRoundNumber = 0;
  @override
  bool _roundCompleteAcknowledged = true;
  @override
  bool _showBombOverlay = false;
  @override
  late final AnimationController _bombController;
  late final Animation<Offset> _bombSlide;
  late final Animation<double> _bombScale;
  @override
  bool _dragonGiveDialogOpen = false;
  @override
  bool _grandTichuDialogOpen = false;
  @override
  bool _wishDialogOpen = false;
  @override
  CardFace? _defaultWishFaceFromSchupf;
  @override
  int _defaultWishRoundNumber = 0;
  @override
  String? _lastAutoConfirmKey;
  @override
  String? _lastAutoPassKey;
  @override
  double _opponentDelaySeconds = 1.0;
  @override
  bool _autoPassEnabled = true;
  @override
  Card? _schupfToLeft;
  @override
  Card? _schupfToPartner;
  @override
  Card? _schupfToRight;
  @override
  Timer? _autoConfirmTimer;
  @override
  bool _schupfAckPending = false;

  @override
  void initState() {
    super.initState();
    _backend = widget._backend ?? LocalGameBackend();
    _bombController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _bombSlide = Tween<Offset>(begin: const Offset(0, -1.6), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _bombController, curve: Curves.easeInCubic),
        );
    _bombScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _bombController, curve: Curves.easeOutBack),
    );
    _bombController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 280), () {
          if (!mounted) return;
          setState(() {
            _showBombOverlay = false;
          });
        });
      }
    });
    _resolvedPlayerControls.addAll({
      'player-0': PlayerControlMode.manual,
      'player-1': PlayerControlMode.ai,
      'player-2': PlayerControlMode.ai,
      'player-3': PlayerControlMode.ai,
    });
    _resolvedPlayerControls.addAll(widget.playerControlModes);
    _selfControlMode =
        _resolvedPlayerControls[_humanId] ?? PlayerControlMode.manual;
    _players = [
      GamePlayer(
        id: 'player-0',
        name: _selfControlMode == PlayerControlMode.ai ? 'You (AI)' : 'You',
        seat: 0,
        type: _toPlayerType(_resolvedPlayerControls['player-0']),
      ),
      GamePlayer(
        id: 'player-1',
        name: 'Opponent 1',
        seat: 1,
        type: _toPlayerType(_resolvedPlayerControls['player-1']),
      ),
      GamePlayer(
        id: 'player-2',
        name: 'Opponent 2 (Partner)',
        seat: 2,
        type: _toPlayerType(_resolvedPlayerControls['player-2']),
      ),
      GamePlayer(
        id: 'player-3',
        name: 'Opponent 3',
        seat: 3,
        type: _toPlayerType(_resolvedPlayerControls['player-3']),
      ),
    ];
    _initializeGame();
  }

  Future<void> _initializeGame() async {
    final gameId = await _backend.createGame(
      _players,
      targetScore: widget._targetScore,
    );
    _subscription = _backend
        .watchGame(gameId, _humanId)
        .listen(_handleSnapshot);
    await _backend.startGame(gameId);
    if (!mounted) return;
    setState(() {
      _gameId = gameId;
    });
  }

  void _handleSnapshot(PlayerSnapshot snapshot) {
    final previousTurn = _snapshot?.lastPlayedTurn;
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      if (_hand.length != snapshot.hand.length) {
        _selectedIndexes.clear();
      }
      _hand = List<Card>.from(snapshot.hand)..sort(_compareCardsForDisplay);
      _trickCards = List<Card>.from(snapshot.deck.turn.cards);
      _pendingOpponentCards = List<Card>.from(snapshot.pendingOpponentCards);
      _pendingOpponentPass = snapshot.pendingOpponentPass;
      final pendingOpponentId = snapshot.pendingOpponentPlayerId;
      _pendingOpponentLabel = pendingOpponentId == null
          ? null
          : snapshot.players
                .firstWhere((player) => player.id == pendingOpponentId)
                .name;
      final dragonKey =
          '${snapshot.lastDragonGiveBy ?? ''}|'
          '${snapshot.lastDragonGiveTo ?? ''}';
      if (snapshot.lastDragonGiveTo == null) {
        _dragonGiveKey = null;
        _dragonGiveTurn = null;
      } else if (_dragonGiveKey != dragonKey) {
        _dragonGiveKey = dragonKey;
        _dragonGiveTurn = snapshot.lastPlayedTurn;
      }
      if (snapshot.phase != GamePhase.schupf ||
          snapshot.schupfCompletedPlayers.contains(_humanId)) {
        _schupfToLeft = null;
        _schupfToPartner = null;
        _schupfToRight = null;
      }
    });

    _handleTurnEffects(previousTurn, snapshot.lastPlayedTurn);
    _maybeShowDragonGiveDialog(snapshot);
    _maybeShowRoundCompleteDialog(snapshot);
    _maybeShowGrandTichuDialog(snapshot);
    _maybeAutoConfirmOpponentTurn(snapshot);
    _maybeAutoPass(snapshot);
    _maybeAutoSelectFinisher(snapshot);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot != null) {
      _maybeShowDragonGiveDialog(snapshot);
    }
    final scoreState = snapshot?.scoreState;
    final playerRoundPoints =
        scoreState?.playerRoundPoints ?? const <String, int>{};
    final finishOrder = scoreState?.finishOrder ?? const <String>[];
    final isRoundComplete = scoreState?.roundComplete ?? false;
    final isGameComplete = scoreState?.gameComplete ?? false;
    int roundPointsFor(String playerId) => playerRoundPoints[playerId] ?? 0;
    int? finishPositionFor(String playerId) {
      final index = finishOrder.indexOf(playerId);
      return index == -1 ? null : index + 1;
    }

    bool isFinished(String playerId) {
      final cardsLeft = snapshot?.opponentCardCounts[playerId];
      return (cardsLeft != null && cardsLeft == 0) ||
          finishPositionFor(playerId) != null;
    }

    final displayHumanScore = roundPointsFor(_humanId);
    final displayPartnerScore = roundPointsFor('player-2');
    final displayLeftScore = roundPointsFor('player-3');
    final displayRightScore = roundPointsFor('player-1');
    final currentPlayerId = snapshot?.currentPlayerId;
    bool isCurrentTurn(String playerId) => currentPlayerId == playerId;
    final isLocalPlayerTurn = isCurrentTurn(_humanId);
    final awaitingOpponentConfirm =
        snapshot?.opponentAwaitingConfirmation ?? false;
    final isSchupfPhase = snapshot?.phase == GamePhase.schupf;
    final isPlayPhase = snapshot?.phase == GamePhase.play;
    final isSchupfActive =
        snapshot != null &&
        isSchupfPhase &&
        !snapshot.schupfCompletedPlayers.contains(_humanId);
    final hasSchupfReceipts =
        snapshot != null && snapshot.schupfReceipts.isNotEmpty;
    final canPlayAny = snapshot != null ? _canPlayAny(snapshot) : false;
    final passPreferred =
      _isSelfManual &&
        isPlayPhase &&
        isLocalPlayerTurn &&
        !isSchupfActive &&
        !hasSchupfReceipts &&
        !awaitingOpponentConfirm &&
        !canPlayAny;
    final canStartRound =
        (isRoundComplete || snapshot == null) &&
        _roundCompleteAcknowledged &&
        !isGameComplete;
    final tichuCalls = scoreState?.tichuCalls ?? const <String, TichuCall>{};
    final playerNames = {
      for (final player in snapshot?.players ?? const <GamePlayer>[])
        player.id: player.name,
    };
    final trickLabel = () {
      if (snapshot == null || _trickCards.isEmpty) return '';
      final lastPlayedBy = snapshot.lastPlayedBy;
      if (lastPlayedBy == null) return '';
      final name = playerNames[lastPlayedBy] ?? 'Unknown';
      return 'Played by $name';
    }();
    final dragonLabel = () {
      if (snapshot == null) return '';
      if (_dragonGiveTurn == null ||
          snapshot.lastPlayedTurn != _dragonGiveTurn) {
        return '';
      }
      final targetId = snapshot.lastDragonGiveTo;
      if (targetId == null) return '';
      final targetName = playerNames[targetId] ?? 'Unknown';
      final byName = snapshot.lastDragonGiveBy == null
          ? null
          : playerNames[snapshot.lastDragonGiveBy!] ?? 'Unknown';
      return byName == null
          ? 'Dragon given to $targetName'
          : 'Dragon given to $targetName by $byName';
    }();
    final centerArea =
        TrickDisplay(
          cards: _trickCards,
          currentWinnerLabel: trickLabel,
          dragonGiveLabel: dragonLabel,
          activeWish: snapshot?.activeWish ?? CardFace.none,
          trickPoints: snapshot?.trickPoints ?? 0,
          pendingOpponentLabel: _pendingOpponentLabel,
          pendingOpponentCards: _pendingOpponentCards,
          pendingOpponentPass: _pendingOpponentPass,
        ).withBombOverlay(
          showOverlay: _showBombOverlay,
          slide: _bombSlide,
          scale: _bombScale,
        );
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 500;
    final schupfHandMaxHeight = (isSchupfActive || hasSchupfReceipts)
        ? screenHeight * (isCompact ? 0.32 : 0.38)
        : null;
    final humanTichuCall = tichuCalls['player-0'];
    final humanTichu =
        humanTichuCall == TichuCall.tichu ||
        humanTichuCall == TichuCall.grandTichu;
    final humanGrandTichu = humanTichuCall == TichuCall.grandTichu;
    final handArea = LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        final showHeader =
            !isCompact && (maxHeight == null || maxHeight >= 120);
        final headerHeight = showHeader ? 30.0 : 0.0;
        final targetHeight = maxHeight == null
            ? null
            : (maxHeight - headerHeight).clamp(60.0, 180.0).toDouble();
        final isSchupfPanel = isSchupfActive || hasSchupfReceipts;
        final content = isSchupfActive
            ? _buildSchupfPanel()
            : hasSchupfReceipts
            ? _buildSchupfReceiptPanel(snapshot, playerNames)
            : HandDisplay(
                cards: _hand,
                selectedIndexes: _selectedIndexes,
                onCardTap: _isSelfManual ? _toggleSelect : (_) {},
                isActive: _isSelfManual && isCurrentTurn(_humanId),
                targetHeight: targetHeight,
              );

        return Column(
          mainAxisSize: maxHeight == null || isSchupfPanel
              ? MainAxisSize.min
              : MainAxisSize.max,
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person, color: Colors.white70, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      'You',
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$displayHumanScore pts',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: Colors.white70),
                    ),
                    if (humanTichu) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: humanGrandTichu
                              ? Colors.deepOrange
                              : Colors.orange,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (humanGrandTichu
                                          ? Colors.deepOrange
                                          : Colors.orange)
                                      .withValues(alpha: 0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Text(
                          humanGrandTichu ? 'GRAND' : 'TICHU',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (maxHeight == null || isSchupfPanel)
              content
            else
              Expanded(child: content),
          ],
        );
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tichu — Single Player Mode'),
        actions: [
          IconButton(
            tooltip: 'Options',
            onPressed: _showOptionsDialog,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'New round',
            onPressed: canStartRound ? _startRound : null,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: SafeArea(
        child: GameBoard(
          topOpponent: OpponentDisplay(
            name: 'Opponent 2 (Partner)',
            cardCount: snapshot?.opponentCardCounts['player-2'] ?? 0,
            isActive: isCurrentTurn('player-2'),
            isFinished: isFinished('player-2'),
            tichuDeclared:
                tichuCalls['player-2'] == TichuCall.tichu ||
                tichuCalls['player-2'] == TichuCall.grandTichu,
            grandTichuDeclared: tichuCalls['player-2'] == TichuCall.grandTichu,
            finishPosition: finishPositionFor('player-2'),
            alignment: Axis.horizontal,
            icon: Icons.psychology_alt,
            pendingCards: snapshot?.pendingOpponentPlayerId == 'player-2'
                ? _pendingOpponentCards
                : const [],
            pendingPass:
                snapshot?.pendingOpponentPlayerId == 'player-2' &&
                _pendingOpponentPass,
            pendingPlacement: PendingPlacement.below,
            teamScore: displayPartnerScore,
          ),
          leftOpponent: OpponentDisplay(
            name: 'Opponent 3',
            cardCount: snapshot?.opponentCardCounts['player-3'] ?? 0,
            isActive: isCurrentTurn('player-3'),
            isFinished: isFinished('player-3'),
            tichuDeclared:
                tichuCalls['player-3'] == TichuCall.tichu ||
                tichuCalls['player-3'] == TichuCall.grandTichu,
            grandTichuDeclared: tichuCalls['player-3'] == TichuCall.grandTichu,
            finishPosition: finishPositionFor('player-3'),
            alignment: Axis.vertical,
            icon: Icons.memory,
            pendingCards: snapshot?.pendingOpponentPlayerId == 'player-3'
                ? _pendingOpponentCards
                : const [],
            pendingPass:
                snapshot?.pendingOpponentPlayerId == 'player-3' &&
                _pendingOpponentPass,
            pendingPlacement: PendingPlacement.right,
            teamScore: displayLeftScore,
          ),
          rightOpponent: OpponentDisplay(
            name: 'Opponent 1',
            cardCount: snapshot?.opponentCardCounts['player-1'] ?? 0,
            isActive: isCurrentTurn('player-1'),
            isFinished: isFinished('player-1'),
            tichuDeclared:
                tichuCalls['player-1'] == TichuCall.tichu ||
                tichuCalls['player-1'] == TichuCall.grandTichu,
            grandTichuDeclared: tichuCalls['player-1'] == TichuCall.grandTichu,
            finishPosition: finishPositionFor('player-1'),
            alignment: Axis.vertical,
            icon: Icons.smart_toy_outlined,
            pendingCards: snapshot?.pendingOpponentPlayerId == 'player-1'
                ? _pendingOpponentCards
                : const [],
            pendingPass:
                snapshot?.pendingOpponentPlayerId == 'player-1' &&
                _pendingOpponentPass,
            pendingPlacement: PendingPlacement.left,
            teamScore: displayRightScore,
          ),
          trickArea: centerArea,
          handArea: handArea,
          handAreaMaxHeightOverride: schupfHandMaxHeight,
          actionBar: ActionBar(
            isPlayEnabled:
              _isSelfManual &&
                snapshot != null &&
                _canPlaySelected(snapshot) &&
                !isSchupfActive &&
                !hasSchupfReceipts &&
                !_schupfAckPending,
            isBombEnabled:
              _isSelfManual &&
                snapshot != null &&
                _canEnableBomb(snapshot) &&
                !isSchupfActive &&
                !hasSchupfReceipts &&
                !_schupfAckPending,
            isPassEnabled:
              _isSelfManual &&
                !isSchupfActive &&
                !hasSchupfReceipts &&
                !_schupfAckPending &&
                isPlayPhase,
            isPassPreferred: passPreferred,
            isSchupfEnabled:
                isSchupfActive &&
                _schupfToLeft != null &&
                _schupfToPartner != null &&
                _schupfToRight != null,
            showSchupf: false,
            showDeclareTichu:
              _isSelfManual &&
                !isRoundComplete &&
                isLocalPlayerTurn &&
                (snapshot?.canCallTichu ?? false) &&
                !humanTichu &&
                isPlayPhase,
            showStartRound: canStartRound,
            onStartRound: _startRound,
            onPlay: _playSelected,
            onBomb: _playBomb,
            onPass: _pass,
            onSchupf: _submitSchupf,
            onDeclareTichu: _declareTichu,
          ),
        ),
      ),
    );
  }

  PlayerType _toPlayerType(PlayerControlMode? mode) {
    if (mode == PlayerControlMode.ai) {
      return PlayerType.automated;
    }
    return PlayerType.human;
  }

  Future<void> _showOptionsDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              title: const Text('Options'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Opponent delay ${_opponentDelaySeconds.toStringAsFixed(0)}s',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _opponentDelaySeconds,
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '${_opponentDelaySeconds.toStringAsFixed(0)}s',
                    onChanged: (value) {
                      setState(() {
                        _opponentDelaySeconds = value;
                      });
                      dialogSetState(() {});
                    },
                  ),
                  SwitchListTile(
                    value: _autoPassEnabled,
                    onChanged: (value) {
                      setState(() {
                        _autoPassEnabled = value;
                      });
                      dialogSetState(() {});
                    },
                    title: const Text('Auto-pass when no legal move'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    final gameId = _gameId;
    if (gameId != null) {
      _backend.disposeGame(gameId);
    }
    _autoConfirmTimer?.cancel();
    _bombController.dispose();
    super.dispose();
  }

  Widget _buildSchupfPanel() {
    final canSubmit =
        _schupfToLeft != null &&
        _schupfToPartner != null &&
        _schupfToRight != null;
    final targetWidth = CardWidget.compactWidth * 1.05;
    final selectedCards = <Card>{
      ...[_schupfToLeft, _schupfToPartner, _schupfToRight].whereType<Card>(),
    };
    final available = _hand
        .where((card) => !selectedCards.contains(card))
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        const minCardHeight = 90.0;
        final maxTargetHeight = maxHeight == null
            ? CardWidget.compactHeight * 0.75
            : (maxHeight * 0.22)
                  .clamp(minCardHeight, CardWidget.compactHeight * 0.75)
                  .toDouble();
        final minScale = minCardHeight / CardWidget.compactHeight;
        final cardScale = (maxTargetHeight / CardWidget.compactHeight).clamp(
          minScale,
          0.9,
        );
        final targetHeight = CardWidget.compactHeight * cardScale;
        final availableHeight = maxHeight == null
            ? 96.0
            : (maxHeight * 0.18).clamp(48.0, 96.0).toDouble();
        final tightGap = maxHeight == null
            ? 4.0
            : (maxHeight * 0.01).clamp(0.0, 4.0).toDouble();
        final looseGap = maxHeight == null
            ? 6.0
            : (maxHeight * 0.015).clamp(0.0, 6.0).toDouble();

        Widget buildTarget({
          required String label,
          required Card? value,
          required VoidCallback onRemove,
          required ValueChanged<Card> onAccept,
        }) {
          return SizedBox(
            width: targetWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: tightGap),
                DragTarget<Card>(
                  onAcceptWithDetails: (details) => onAccept(details.data),
                  builder: (context, candidateData, rejectedData) {
                    final isActive = candidateData.isNotEmpty;
                    return GestureDetector(
                      onTap: value == null ? null : onRemove,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: EdgeInsets.zero,
                        height: targetHeight,
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.amber.withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive ? Colors.amber : Colors.white24,
                          ),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Center(
                          child: value == null
                              ? Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.white38,
                                  size: 26,
                                )
                              : CardWidget(
                                  card: value,
                                  isSelected: false,
                                  compact: true,
                                  scale: cardScale,
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        }

        final content = Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(
              'Schupf your cards',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: tightGap),
            Text(
              'Drag one card to each target.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            SizedBox(height: looseGap),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                buildTarget(
                  label: 'Left opponent',
                  value: _schupfToRight,
                  onRemove: () => _clearSchupfSlot(_SchupfSlot.right),
                  onAccept: (card) => _setSchupfSlot(_SchupfSlot.right, card),
                ),
                const SizedBox(width: 12),
                buildTarget(
                  label: 'Partner',
                  value: _schupfToPartner,
                  onRemove: () => _clearSchupfSlot(_SchupfSlot.partner),
                  onAccept: (card) => _setSchupfSlot(_SchupfSlot.partner, card),
                ),
                const SizedBox(width: 12),
                buildTarget(
                  label: 'Right opponent',
                  value: _schupfToLeft,
                  onRemove: () => _clearSchupfSlot(_SchupfSlot.left),
                  onAccept: (card) => _setSchupfSlot(_SchupfSlot.left, card),
                ),
              ],
            ),
            SizedBox(height: tightGap),
            Center(
              child: ElevatedButton.icon(
                onPressed: canSubmit ? _submitSchupf : null,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Send Schupf'),
              ),
            ),
            SizedBox(height: tightGap),
            SizedBox(
              height: availableHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = (availableHeight / CardWidget.compactHeight)
                      .clamp(0.5, 0.9);
                  final cardW = CardWidget.compactWidth * scale;
                  final cardH = CardWidget.compactHeight * scale;
                  final spacing = 6 * scale;

                  return OverlappingCardRow(
                    itemCount: available.length,
                    cardWidth: cardW,
                    cardHeight: cardH,
                    spacing: spacing,
                    minVisible: 14 * scale,
                    height: cardH + 8,
                    itemBuilder: (context, index) {
                      final card = available[index];
                      void onQuickAssign() {
                        if (_schupfToLeft == null) {
                          _setSchupfSlot(_SchupfSlot.left, card);
                        } else if (_schupfToPartner == null) {
                          _setSchupfSlot(_SchupfSlot.partner, card);
                        } else if (_schupfToRight == null) {
                          _setSchupfSlot(_SchupfSlot.right, card);
                        }
                      }

                      Widget buildCard() {
                        return GestureDetector(
                          onDoubleTap: onQuickAssign,
                          child: CardWidget(
                            card: card,
                            isSelected: false,
                            compact: true,
                            scale: scale,
                          ),
                        );
                      }

                      return Draggable<Card>(
                        data: card,
                        feedback: Material(
                          color: Colors.transparent,
                          child: CardWidget(
                            card: card,
                            isSelected: false,
                            compact: true,
                            scale: scale,
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.4,
                          child: buildCard(),
                        ),
                        child: buildCard(),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: maxHeight == null
              ? content
              : SizedBox(height: maxHeight, child: content),
        );
      },
    );
  }

  Widget _buildSchupfReceiptPanel(
    PlayerSnapshot snapshot,
    Map<String, String> playerNames,
  ) {
    final receipts = snapshot.schupfReceipts;
    final receiptByDirection = {
      for (final receipt in receipts) receipt.direction: receipt,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        final targetWidth = CardWidget.compactWidth * 1.05;
        final naturalTargetH = CardWidget.compactHeight * 0.9 + 72;
        final targetHeight = maxH == null
            ? naturalTargetH
            : (maxH * 0.42).clamp(90.0, naturalTargetH).toDouble();
        final cardScale = (targetHeight / (CardWidget.compactHeight + 50))
            .clamp(0.6, 0.9);

        Widget buildTarget({
          required String label,
          required SchupfReceipt? receipt,
        }) {
          final fromName = receipt == null
              ? 'Waiting'
              : playerNames[receipt.fromPlayerId] ?? 'Unknown';
          return SizedBox(
            width: targetWidth,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(6),
              height: targetHeight,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              clipBehavior: Clip.hardEdge,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fromName,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: Colors.white54),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  if (receipt == null)
                    Icon(Icons.hourglass_empty, color: Colors.white38, size: 24)
                  else
                    Flexible(
                      child: CardWidget(
                        card: receipt.card,
                        isSelected: false,
                        compact: true,
                        scale: cardScale,
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Schupf received',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Review your cards before starting the round.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    buildTarget(
                      label: 'Left',
                      receipt: receiptByDirection[SchupfDirection.right],
                    ),
                    const SizedBox(width: 8),
                    buildTarget(
                      label: 'Partner',
                      receipt: receiptByDirection[SchupfDirection.partner],
                    ),
                    const SizedBox(width: 8),
                    buildTarget(
                      label: 'Right',
                      receipt: receiptByDirection[SchupfDirection.left],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _schupfAckPending
                      ? null
                      : _acknowledgeSchupfReceipts,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    _schupfAckPending ? 'Accepting…' : 'Accept schupf',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _setSchupfSlot(_SchupfSlot slot, Card card) {
    setState(() {
      if (_schupfToLeft == card) _schupfToLeft = null;
      if (_schupfToPartner == card) _schupfToPartner = null;
      if (_schupfToRight == card) _schupfToRight = null;

      switch (slot) {
        case _SchupfSlot.left:
          _schupfToLeft = card;
        case _SchupfSlot.partner:
          _schupfToPartner = card;
        case _SchupfSlot.right:
          _schupfToRight = card;
      }
    });
  }

  void _clearSchupfSlot(_SchupfSlot slot) {
    setState(() {
      switch (slot) {
        case _SchupfSlot.left:
          _schupfToLeft = null;
        case _SchupfSlot.partner:
          _schupfToPartner = null;
        case _SchupfSlot.right:
          _schupfToRight = null;
      }
    });
  }
}

enum _SchupfSlot { left, partner, right }
