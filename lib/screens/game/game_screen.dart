import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:tichu/game/driver_ui_projector.dart';
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
import '../shared/keyboard_shortcuts.dart';
import 'widgets/trick_event_overlay.dart';
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
  }) : _backend = backend,
       _targetScore = targetScore;

  final GameBackend? _backend;
  final int _targetScore;
  final Map<String, PlayerControlMode> playerControlModes;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with
        TickerProviderStateMixin,
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
  final DriverUiProjector _uiProjector = const DriverUiProjector();
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
  String? _pendingOpponentPlayerId;
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
  double _opponentDelaySeconds = 2.0;
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

  bool _grandTichuSelectNo = true;
  int? _schupfCursorIndex;
  final FocusNode _schupfFocusNode = FocusNode();

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
    _opponentDelaySeconds = _isSelfManual ? 1.0 : 2.0;
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
        name: 'Opponent 2',
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
    final delayMs = (_opponentDelaySeconds * 1000).round();
    await _backend.setAutomatedActionDelay(Duration(milliseconds: delayMs));
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
    final wasShowingGrandTichuDecision =
        _snapshot != null && _shouldShowGrandTichuDecision(_snapshot!);
    if (!mounted) return;
    if (!snapshot.opponentAwaitingConfirmation) {
      _lastAutoConfirmKey = null;
      _autoConfirmTimer?.cancel();
      _autoConfirmTimer = null;
    }
    setState(() {
      _snapshot = snapshot;
      if (_schupfAckPending && snapshot.schupfReceipts.isEmpty) {
        _schupfAckPending = false;
      }
      if (_hand.length != snapshot.hand.length) {
        _selectedIndexes.clear();
      }
      _hand = List<Card>.from(snapshot.hand)..sort(_compareCardsForDisplay);
      _trickCards = List<Card>.from(snapshot.deck.turn.cards);
      final uiProjection = _uiProjector.project(
        snapshot: snapshot,
        humanId: _humanId,
        isSelfManual: _isSelfManual,
        hand: _hand,
        currentSelectedIndexes: _selectedIndexes,
        currentSchupfToLeft: _schupfToLeft,
        currentSchupfToPartner: _schupfToPartner,
        currentSchupfToRight: _schupfToRight,
      );
      _pendingOpponentCards = uiProjection.pendingOpponentCards;
      _pendingOpponentPass = uiProjection.pendingOpponentPass;
      _pendingOpponentPlayerId = uiProjection.pendingOpponentPlayerId;
      _pendingOpponentLabel = _pendingOpponentPlayerId == null
          ? null
          : snapshot.players
                .firstWhere((player) => player.id == _pendingOpponentPlayerId)
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
      _schupfToLeft = uiProjection.schupfToLeft;
      _schupfToPartner = uiProjection.schupfToPartner;
      _schupfToRight = uiProjection.schupfToRight;
      _selectedIndexes
        ..clear()
        ..addAll(uiProjection.selectedIndexes);

      // Initialize / reset schupf keyboard cursor.
      final isSchupfActive =
          snapshot.phase == GamePhase.schupf &&
          !snapshot.schupfCompletedPlayers.contains(_humanId);
      if (isSchupfActive && _schupfCursorIndex == null) {
        _syncSchupfCursor(defaultToRightMost: true);
      } else if (!isSchupfActive) {
        _schupfCursorIndex = null;
      }

      final isShowingGrandTichuDecision = _shouldShowGrandTichuDecision(
        snapshot,
      );
      if (isShowingGrandTichuDecision && !wasShowingGrandTichuDecision) {
        _grandTichuSelectNo = true;
      }
    });

    _handleTurnEffects(previousTurn, snapshot.lastPlayedTurn);
    _maybeShowDragonGiveDialog(snapshot);
    _maybeShowRoundCompleteDialog(snapshot);
    _maybeAutoConfirmOpponentTurn(snapshot);
    _maybeAutoPass(snapshot);
    _maybeAutoSelectFinisher(snapshot);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _schupfFocusNode.requestFocus();
    });
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
    final phase = snapshot?.phase;

    // ── Phase: schupf ──────────────────────────────────────────────────
    final isSchupfActive =
        snapshot != null &&
        phase == GamePhase.schupf &&
        !snapshot.schupfCompletedPlayers.contains(_humanId);
    final hasSchupfReceipts =
        !_schupfAckPending &&
        snapshot != null &&
        snapshot.schupfReceipts.isNotEmpty;

    // ── Phase: play ────────────────────────────────────────────────────
    final isPlayPhase = phase == GamePhase.play;
    final pendingReceipts =
        _schupfAckPending ||
        (snapshot != null && snapshot.schupfReceipts.isNotEmpty);
    final showTurnIndicators = isPlayPhase && !pendingReceipts;
    final showTurnActions = isPlayPhase && !pendingReceipts;
    final canPlayAny = snapshot != null ? _canPlayAny(snapshot) : false;
    final canPass = snapshot != null ? _canPass(snapshot) : false;
    final passPreferred =
        _isSelfManual &&
        showTurnActions &&
        isLocalPlayerTurn &&
        !(snapshot?.opponentAwaitingConfirmation ?? false) &&
        canPass &&
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
    final showOpponentPendingCards = isPlayPhase;
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 500;
    final humanTichuCall = tichuCalls['player-0'];
    final humanTichu =
        humanTichuCall == TichuCall.tichu ||
        humanTichuCall == TichuCall.grandTichu;
    final humanGrandTichu = humanTichuCall == TichuCall.grandTichu;
    final showGrandTichuDecision =
        snapshot != null && _shouldShowGrandTichuDecision(snapshot);
    final grandTichuDecisionPending = _grandTichuDialogOpen;
    final handArea = LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        final showHeader =
            !isCompact && (maxHeight == null || maxHeight >= 120);
        // Header (30) + gap (4) + container padding (12) are inside HandDisplay.
        final handDisplayOverhead = showHeader ? 46.0 : 12.0;
        final targetHeight = maxHeight == null
            ? null
            : (maxHeight - handDisplayOverhead).clamp(60.0, 180.0).toDouble();
        final isSchupfPanel = isSchupfActive || hasSchupfReceipts;

        final headerWidget = showHeader
            ? Row(
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
                  if (isPlayPhase) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$displayHumanScore pts',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: Colors.white70),
                    ),
                  ],
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
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ],
              )
            : null;

        final handDisplay = HandDisplay(
          cards: _hand,
          selectedIndexes: _selectedIndexes,
          onCardTap: _isSelfManual ? _toggleSelect : (_) {},
          isActive: showTurnIndicators && isCurrentTurn(_humanId),
          isFinished: isFinished(_humanId),
          finishPosition: finishPositionFor(_humanId),
          targetHeight: targetHeight,
          header: headerWidget,
        );

        final baseContent = isSchupfActive
            ? _buildSchupfPanel()
            : hasSchupfReceipts
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSchupfReceiptPanel(snapshot),
                  const SizedBox(height: 8),
                  HandDisplay(
                    cards: _hand,
                    selectedIndexes: _selectedIndexes,
                    onCardTap: _isSelfManual ? _toggleSelect : (_) {},
                    isActive: showTurnIndicators && isCurrentTurn(_humanId),
                    isFinished: isFinished(_humanId),
                    finishPosition: finishPositionFor(_humanId),
                    targetHeight: targetHeight,
                    header: null,
                  ),
                ],
              )
            : handDisplay;

        final winningTeam = scoreState?.winningTeam;
        final showMatchPanel = isGameComplete && winningTeam != null;
        final content = showGrandTichuDecision
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  baseContent,
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Grand Tichu?',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 64,
                            child: _grandTichuSelectNo
                                ? ElevatedButton(
                                    onPressed: grandTichuDecisionPending
                                        ? null
                                        : () =>
                                              _submitGrandTichuDecision(false),
                                    child: const Text('No'),
                                  )
                                : TextButton(
                                    onPressed: grandTichuDecisionPending
                                        ? null
                                        : () {
                                            setState(() {
                                              _grandTichuSelectNo = true;
                                            });
                                          },
                                    child: const Text('No'),
                                  ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 64,
                            child: !_grandTichuSelectNo
                                ? ElevatedButton(
                                    onPressed: grandTichuDecisionPending
                                        ? null
                                        : () => _submitGrandTichuDecision(true),
                                    child: const Text('Yes'),
                                  )
                                : TextButton(
                                    onPressed: grandTichuDecisionPending
                                        ? null
                                        : () {
                                            setState(() {
                                              _grandTichuSelectNo = false;
                                            });
                                          },
                                    child: const Text('Yes'),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : baseContent;

        final handContent = showMatchPanel
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  content,
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '\u{1F3C6} ${winningTeam == 0 ? 'Your team wins!' : 'Other team wins!'}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text('Continue'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : content;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHeader && isSchupfPanel)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: headerWidget!,
              ),
            handContent,
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
        ],
      ),
      body: Focus(
        focusNode: _schupfFocusNode,
        autofocus: true,
        onKeyEvent: (node, event) => handleDirectionalEnterKeyEvent(
          event,
          onEnter: _handleShortcutEnter,
          onLeft: _handleShortcutLeft,
          onRight: _handleShortcutRight,
        ),
        child: SafeArea(
          child: GameBoard(
            topOpponent: OpponentDisplay(
              name: 'Opponent 2',
              cardCount: snapshot?.opponentCardCounts['player-2'] ?? 0,
              isActive: showTurnIndicators && isCurrentTurn('player-2'),
              isFinished: isFinished('player-2'),
              tichuDeclared:
                  tichuCalls['player-2'] == TichuCall.tichu ||
                  tichuCalls['player-2'] == TichuCall.grandTichu,
              grandTichuDeclared:
                  tichuCalls['player-2'] == TichuCall.grandTichu,
              finishPosition: finishPositionFor('player-2'),
              alignment: Axis.horizontal,
              icon: Icons.psychology_alt,
              pendingCards:
                  showOpponentPendingCards &&
                      _pendingOpponentPlayerId == 'player-2'
                  ? _pendingOpponentCards
                  : const [],
              pendingPass:
                  showOpponentPendingCards &&
                  _pendingOpponentPlayerId == 'player-2' &&
                  _pendingOpponentPass,
              pendingPlacement: PendingPlacement.below,
              teamScore: displayPartnerScore,
              showPoints: isPlayPhase,
            ),
            leftOpponent: OpponentDisplay(
              name: 'Opponent 3',
              cardCount: snapshot?.opponentCardCounts['player-3'] ?? 0,
              isActive: showTurnIndicators && isCurrentTurn('player-3'),
              isFinished: isFinished('player-3'),
              tichuDeclared:
                  tichuCalls['player-3'] == TichuCall.tichu ||
                  tichuCalls['player-3'] == TichuCall.grandTichu,
              grandTichuDeclared:
                  tichuCalls['player-3'] == TichuCall.grandTichu,
              finishPosition: finishPositionFor('player-3'),
              alignment: Axis.vertical,
              icon: Icons.memory,
              pendingCards:
                  showOpponentPendingCards &&
                      _pendingOpponentPlayerId == 'player-3'
                  ? _pendingOpponentCards
                  : const [],
              pendingPass:
                  showOpponentPendingCards &&
                  _pendingOpponentPlayerId == 'player-3' &&
                  _pendingOpponentPass,
              pendingPlacement: PendingPlacement.right,
              teamScore: displayLeftScore,
              showPoints: isPlayPhase,
            ),
            rightOpponent: OpponentDisplay(
              name: 'Opponent 1',
              cardCount: snapshot?.opponentCardCounts['player-1'] ?? 0,
              isActive: showTurnIndicators && isCurrentTurn('player-1'),
              isFinished: isFinished('player-1'),
              tichuDeclared:
                  tichuCalls['player-1'] == TichuCall.tichu ||
                  tichuCalls['player-1'] == TichuCall.grandTichu,
              grandTichuDeclared:
                  tichuCalls['player-1'] == TichuCall.grandTichu,
              finishPosition: finishPositionFor('player-1'),
              alignment: Axis.vertical,
              icon: Icons.smart_toy_outlined,
              pendingCards:
                  showOpponentPendingCards &&
                      _pendingOpponentPlayerId == 'player-1'
                  ? _pendingOpponentCards
                  : const [],
              pendingPass:
                  showOpponentPendingCards &&
                  _pendingOpponentPlayerId == 'player-1' &&
                  _pendingOpponentPass,
              pendingPlacement: PendingPlacement.left,
              teamScore: displayRightScore,
              showPoints: isPlayPhase,
            ),
            trickArea: centerArea,
            handArea: handArea,
            actionBar: ActionBar(
              showTurnActions: showTurnActions,
              isPlayEnabled:
                  _isSelfManual &&
                  snapshot != null &&
                  _canPlaySelected(snapshot) &&
                  !pendingReceipts,
              isBombEnabled:
                  _isSelfManual &&
                  snapshot != null &&
                  _canEnableBomb(snapshot) &&
                  !pendingReceipts,
              isPassEnabled:
                  _isSelfManual && isPlayPhase && !pendingReceipts && canPass,
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
                  (snapshot?.canCallTichu ?? false) &&
                  !humanTichu,
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
      ),
    );
  }

  PlayerType _toPlayerType(PlayerControlMode? mode) {
    if (mode == PlayerControlMode.ai) {
      return PlayerType.automated;
    }
    return PlayerType.human;
  }

  @override
  void _requestKeyboardFocus() {
    if (!mounted) return;
    _schupfFocusNode.requestFocus();
  }

  void _handleShortcutEnter() {
    final snapshot = _snapshot;
    if (snapshot == null) return;

    if (_shouldShowGrandTichuDecision(snapshot)) {
      _submitGrandTichuDecision(!_grandTichuSelectNo);
      return;
    }

    final isSchupfActive =
        snapshot.phase == GamePhase.schupf &&
        !snapshot.schupfCompletedPlayers.contains(_humanId);
    if (isSchupfActive) {
      final canSubmit =
          _schupfToLeft != null &&
          _schupfToPartner != null &&
          _schupfToRight != null;
      if (canSubmit) {
        _submitSchupf();
        return;
      }

      final selectedCards = <Card>{
        ...[_schupfToLeft, _schupfToPartner, _schupfToRight].whereType<Card>(),
      };
      final available = _hand.where((c) => !selectedCards.contains(c)).toList();
      if (available.isEmpty) return;
      final cursor = (_schupfCursorIndex ?? (available.length - 1)).clamp(
        0,
        available.length - 1,
      );
      final card = available[cursor];
      if (_schupfToRight == null) {
        _setSchupfSlot(_SchupfSlot.right, card);
      } else if (_schupfToPartner == null) {
        _setSchupfSlot(_SchupfSlot.partner, card);
      } else if (_schupfToLeft == null) {
        _setSchupfSlot(_SchupfSlot.left, card);
      }
      return;
    }

    // Acknowledge schupf receipts with Enter.
    if (snapshot.schupfReceipts.isNotEmpty && !_schupfAckPending) {
      _acknowledgeSchupfReceipts();
      return;
    }

    if (!_isSelfManual || snapshot.phase != GamePhase.play) {
      return;
    }
    final pendingReceipts =
        _schupfAckPending || snapshot.schupfReceipts.isNotEmpty;
    final canPlay = !pendingReceipts && _canPlaySelected(snapshot);
    if (!canPlay) return;
    _playSelected();
  }

  void _handleShortcutLeft() {
    final snapshot = _snapshot;
    if (snapshot == null) return;

    if (_shouldShowGrandTichuDecision(snapshot)) {
      setState(() {
        _grandTichuSelectNo = true;
      });
      return;
    }

    final isSchupfActive =
        snapshot.phase == GamePhase.schupf &&
        !snapshot.schupfCompletedPlayers.contains(_humanId);
    if (!isSchupfActive) return;

    final canSubmit =
        _schupfToLeft != null &&
        _schupfToPartner != null &&
        _schupfToRight != null;
    if (canSubmit) return;

    final selectedCards = <Card>{
      ...[_schupfToLeft, _schupfToPartner, _schupfToRight].whereType<Card>(),
    };
    final available = _hand.where((c) => !selectedCards.contains(c)).toList();
    if (available.isEmpty) return;

    final cursor = _schupfCursorIndex ?? (available.length - 1);
    setState(() {
      _schupfCursorIndex = (cursor - 1).clamp(0, available.length - 1);
    });
  }

  void _handleShortcutRight() {
    final snapshot = _snapshot;
    if (snapshot == null) return;

    if (_shouldShowGrandTichuDecision(snapshot)) {
      setState(() {
        _grandTichuSelectNo = false;
      });
      return;
    }

    final isSchupfActive =
        snapshot.phase == GamePhase.schupf &&
        !snapshot.schupfCompletedPlayers.contains(_humanId);
    if (!isSchupfActive) return;

    final canSubmit =
        _schupfToLeft != null &&
        _schupfToPartner != null &&
        _schupfToRight != null;
    if (canSubmit) return;

    final selectedCards = <Card>{
      ...[_schupfToLeft, _schupfToPartner, _schupfToRight].whereType<Card>(),
    };
    final available = _hand.where((c) => !selectedCards.contains(c)).toList();
    if (available.isEmpty) return;

    final cursor = _schupfCursorIndex ?? (available.length - 1);
    setState(() {
      _schupfCursorIndex = (cursor + 1).clamp(0, available.length - 1);
    });
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
                      final delayMs = (_opponentDelaySeconds * 1000).round();
                      _backend.setAutomatedActionDelay(
                        Duration(milliseconds: delayMs),
                      );
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
    _schupfFocusNode.dispose();
    super.dispose();
  }

  Widget _buildSchupfPanel() {
    final canSubmit =
        _schupfToLeft != null &&
        _schupfToPartner != null &&
        _schupfToRight != null;
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
        final targetCardWidth = CardWidget.compactWidth * cardScale;
        final targetCardHeight = CardWidget.compactHeight * cardScale;
        const targetInset = 8.0;
        final targetWidth = targetCardWidth + (targetInset * 2);
        final targetHeight = targetCardHeight + (targetInset * 2);
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
          return DragTarget<Card>(
            onAcceptWithDetails: (details) => onAccept(details.data),
            builder: (context, candidateData, rejectedData) {
              final isActive = candidateData.isNotEmpty;
              return _buildSchupfTargetBox(
                label: label,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                labelGap: tightGap,
                content: value == null
                    ? const Icon(
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
                onTap: value == null ? null : onRemove,
                isActive: isActive,
                targetInset: targetInset,
              );
            },
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
            SizedBox(height: tightGap + looseGap),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                buildTarget(
                  label: 'Left',
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
                  label: 'Right',
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
                style: ElevatedButton.styleFrom(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 0.6,
                  ),
                ),
                label: const Text('Schupf'),
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
                        if (_schupfToRight == null) {
                          _setSchupfSlot(_SchupfSlot.right, card);
                        } else if (_schupfToPartner == null) {
                          _setSchupfSlot(_SchupfSlot.partner, card);
                        } else if (_schupfToLeft == null) {
                          _setSchupfSlot(_SchupfSlot.left, card);
                        }
                      }

                      final isCursor = _schupfCursorIndex == index;

                      Widget buildCard() {
                        return GestureDetector(
                          onDoubleTap: onQuickAssign,
                          child: CardWidget(
                            card: card,
                            isSelected: isCursor,
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

  Widget _buildSchupfReceiptPanel(PlayerSnapshot snapshot) {
    final receipts = snapshot.schupfReceipts;
    final receiptByDirection = {
      for (final receipt in receipts) receipt.direction: receipt,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        const minCardHeight = 90.0;
        final maxTargetHeight = maxH == null
            ? CardWidget.compactHeight * 0.75
            : (maxH * 0.22)
                  .clamp(minCardHeight, CardWidget.compactHeight * 0.75)
                  .toDouble();
        final minScale = minCardHeight / CardWidget.compactHeight;
        final cardScale = (maxTargetHeight / CardWidget.compactHeight).clamp(
          minScale,
          0.9,
        );
        final tightGap = maxH == null
            ? 4.0
            : (maxH * 0.01).clamp(0.0, 4.0).toDouble();
        const targetInset = 8.0;
        final targetWidth =
            CardWidget.compactWidth * cardScale + (targetInset * 2);
        final targetHeight =
            CardWidget.compactHeight * cardScale + (targetInset * 2);

        Widget buildTarget({
          required String label,
          required SchupfReceipt? receipt,
        }) {
          return _buildSchupfTargetBox(
            label: label,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            labelGap: tightGap,
            content: receipt == null
                ? const Icon(
                    Icons.hourglass_empty,
                    color: Colors.white38,
                    size: 24,
                  )
                : CardWidget(
                    card: receipt.card,
                    isSelected: false,
                    compact: true,
                    scale: cardScale,
                  ),
            targetInset: targetInset,
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
                  label: const Text('PLAY'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSchupfTargetBox({
    required String label,
    required double targetWidth,
    required double targetHeight,
    required Widget content,
    bool isActive = false,
    double labelGap = 4,
    VoidCallback? onTap,
    double targetInset = 8,
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
          SizedBox(height: labelGap),
          GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: targetWidth,
              height: targetHeight,
              padding: EdgeInsets.all(targetInset),
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
              child: Center(child: content),
            ),
          ),
        ],
      ),
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
      _syncSchupfCursor(defaultToRightMost: true);
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
      _syncSchupfCursor(defaultToRightMost: true);
    });
  }

  void _syncSchupfCursor({required bool defaultToRightMost}) {
    final canSubmit =
        _schupfToLeft != null &&
        _schupfToPartner != null &&
        _schupfToRight != null;
    if (canSubmit) {
      _schupfCursorIndex = null;
      return;
    }

    final selectedCards = <Card>{
      ...[_schupfToLeft, _schupfToPartner, _schupfToRight].whereType<Card>(),
    };
    final available = _hand.where((c) => !selectedCards.contains(c)).length;
    if (available == 0) {
      _schupfCursorIndex = null;
      return;
    }

    if (_schupfCursorIndex == null) {
      _schupfCursorIndex = defaultToRightMost ? available - 1 : 0;
      return;
    }
    _schupfCursorIndex = _schupfCursorIndex!.clamp(0, available - 1);
  }
}

enum _SchupfSlot { left, partner, right }
