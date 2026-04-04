import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/driver_ui_projector.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/game_play_controller.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/wish_logic.dart';
import 'package:tichu/screens/game/round_summary_screen.dart';
import 'package:tichu/screens/game/widgets/game_board.dart';
import 'package:tichu/screens/game/widgets/grand_tichu_banner.dart';
import 'package:tichu/screens/game/widgets/options_dialog.dart';
import 'package:tichu/screens/game/widgets/player_hand_area.dart';
import 'package:tichu/screens/game/widgets/schupf_layout.dart';
import 'package:tichu/screens/game/widgets/tichu_celebration_overlay.dart';
import 'package:tichu/screens/game/widgets/trick_event_overlay.dart';
import 'package:tichu/screens/game/widgets/wish_dialog.dart';
import 'package:tichu/screens/shared/keyboard_shortcuts.dart';
import 'package:tichu/screens/shared/player_control.dart';
import 'package:tichu/services/sound_effects.dart';
import 'package:tichu/widgets/action_bar.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/opponent_display.dart';
import 'package:tichu/widgets/pending_play_slot.dart';
import 'package:tichu/widgets/trick_display.dart';

part 'parts/game_screen_actions.dart';
part 'parts/game_screen_dialogs.dart';
part 'parts/game_screen_logic.dart';
part 'parts/game_screen_state_bindings.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required final GameBackend backend,
    final int targetScore = 1000,
    this.playerControlModes = const {},
  }) : _backend = backend,
       _targetScore = targetScore;
  final GameBackend _backend;
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
  final DriverUiProjector _uiProjector = const DriverUiProjector();
  @override
  late final GamePlayController _playController = GamePlayController();
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
  double _opponentDelaySeconds = 2;
  @override
  bool _autoPassEnabled = true;
  @override
  bool _soundEnabled = SoundEffects.enabled;
  @override
  bool _aiSuggestionEnabled = true;
  @override
  bool _aiSuggestionSelectionOwned = false;
  @override
  Card? _schupfToLeft;
  @override
  Card? _schupfToPartner;
  @override
  Card? _schupfToRight;
  @override
  List<Card> _schupfSentCards = <Card>[];
  @override
  Timer? _autoConfirmTimer;
  @override
  bool _schupfAckPending = false;

  bool _grandTichuSelectNo = true;
  int? _schupfCursorIndex;
  final FocusNode _schupfFocusNode = FocusNode();
  late final SmartAiAgent _suggestionAgent;
  int _aiSuggestionRequestId = 0;

  @override
  void initState() {
    super.initState();
    _backend = widget._backend;
    _bombController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _bombSlide = Tween<Offset>(begin: const Offset(0, -1.6), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _bombController, curve: Curves.easeInCubic),
        );
    _bombScale = Tween<double>(begin: 0.85, end: 1).animate(
      CurvedAnimation(parent: _bombController, curve: Curves.easeOutBack),
    );
    _bombController.addStatusListener((final status) {
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
    _suggestionAgent = SmartAiAgent(_humanId);
    _opponentDelaySeconds = 1.0;
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
    unawaited(_initializeGame());
  }

  Future<void> _initializeGame() async {
    unawaited(CardWidget.precacheCardAssets(context));

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

  void _handleSnapshot(final PlayerSnapshot snapshot) {
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
        _schupfSentCards = <Card>[];
      }
      if (snapshot.schupfReceipts.isEmpty &&
          snapshot.phase != GamePhase.schupf) {
        _schupfSentCards = <Card>[];
      }
      if (_hand.length != snapshot.hand.length) {
        _selectedIndexes.clear();
        _aiSuggestionSelectionOwned = false;
      }
      _hand = List<Card>.from(snapshot.hand)..sort(compareCardsForDisplay);
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
      if (snapshot.scoreState.roundNumber != _defaultWishRoundNumber) {
        _defaultWishFaceFromSchupf = null;
      }
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
      _aiSuggestionSelectionOwned = false;

      // Initialize / reset schupf keyboard cursor.
      final isSchupfActive =
          snapshot.phase == GamePhase.schupf &&
          !snapshot.schupfCompletedPlayers.contains(_humanId);
      if (_hasKeyboardForSchupf &&
          isSchupfActive &&
          _schupfCursorIndex == null) {
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
    unawaited(_maybeApplyAiSuggestion(snapshot));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _schupfFocusNode.requestFocus();
    });
  }

  @override
  Future<void> _maybeApplyAiSuggestion(final PlayerSnapshot snapshot) async {
    if (!_isSelfManual || !_aiSuggestionEnabled) {
      _clearAiSuggestionSelection();
      return;
    }
    if (snapshot.phase != GamePhase.play ||
        snapshot.currentPlayerId != _humanId) {
      _clearAiSuggestionSelection();
      return;
    }
    if (snapshot.pendingDragonGiveBy == _humanId) {
      _clearAiSuggestionSelection();
      return;
    }
    if (_schupfAckPending || snapshot.schupfReceipts.isNotEmpty) {
      _clearAiSuggestionSelection();
      return;
    }

    final isLeading =
        snapshot.deck.turn.type == TurnType.empty ||
        snapshot.deck.turn.type == TurnType.none;
    if (isLeading) {
      _clearAiSuggestionSelection();
      return;
    }

    if (_selectedIndexes.isNotEmpty && !_aiSuggestionSelectionOwned) {
      return;
    }

    final requestId = ++_aiSuggestionRequestId;
    final aiSnapshot = _buildAiSuggestionSnapshot(snapshot);
    final action = await _suggestionAgent.selectTurn(aiSnapshot);
    if (!mounted || requestId != _aiSuggestionRequestId) return;

    if (action is! PlayTurnAction) {
      _clearAiSuggestionSelection();
      return;
    }

    final suggestedIndexes = _playController.cardIndicesInHand(
      _hand,
      action.cards,
    );
    if (suggestedIndexes.isEmpty) {
      _clearAiSuggestionSelection();
      return;
    }

    final suggestedCards = [for (final index in suggestedIndexes) _hand[index]];
    final suggestedTurn = _playController.resolveSelectedTurn(
      snapshot: snapshot,
      selectedCards: suggestedCards,
      hand: _hand,
    );
    if (suggestedTurn == null) {
      _clearAiSuggestionSelection();
      return;
    }

    setState(() {
      _selectedIndexes
        ..clear()
        ..addAll(suggestedIndexes);
      _aiSuggestionSelectionOwned = true;
    });
  }

  @override
  void _clearAiSuggestionSelection() {
    _aiSuggestionRequestId += 1;
    if (!_aiSuggestionSelectionOwned || _selectedIndexes.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _selectedIndexes.clear();
      _aiSuggestionSelectionOwned = false;
    });
  }

  GameSnapshot _buildAiSuggestionSnapshot(final PlayerSnapshot snapshot) {
    final hands = <String, List<Card>>{};
    for (final player in snapshot.players) {
      if (player.id == _humanId) {
        hands[player.id] = List<Card>.from(_hand);
        continue;
      }
      final count = snapshot.opponentCardCounts[player.id] ?? 0;
      hands[player.id] = List<Card>.generate(
        count,
        (_) => Card(CardFace.none, CardColor.special),
      );
    }

    return GameSnapshot(
      gameId: snapshot.gameId,
      players: snapshot.players,
      hands: hands,
      deck: snapshot.deck,
      trickPoints: snapshot.trickPoints,
      activeWish: snapshot.activeWish,
      currentPlayerId: snapshot.currentPlayerId,
      consecutivePasses: snapshot.consecutivePasses,
      lastPlayedBy: snapshot.lastPlayedBy,
      lastPlayedTurn: snapshot.lastPlayedTurn,
      lastDragonGiveBy: snapshot.lastDragonGiveBy,
      lastDragonGiveTo: snapshot.lastDragonGiveTo,
      pendingDragonGiveBy: snapshot.pendingDragonGiveBy,
      pendingDragonGiveTargets: snapshot.pendingDragonGiveTargets,
      pendingOpponentPlayerId: snapshot.pendingOpponentPlayerId,
      pendingOpponentCards: snapshot.pendingOpponentCards,
      pendingOpponentPass: snapshot.pendingOpponentPass,
      scoreState: snapshot.scoreState,
      opponentAwaitingConfirmation: snapshot.opponentAwaitingConfirmation,
      phase: snapshot.phase,
      canCallTichuByPlayer: {
        for (final player in snapshot.players)
          player.id: player.id == _humanId && snapshot.canCallTichu,
      },
      hasBombByPlayer: {
        for (final player in snapshot.players)
          player.id: player.id == _humanId && snapshot.hasBombInHand,
      },
      canBombByPlayer: {
        for (final player in snapshot.players)
          player.id: player.id == _humanId && snapshot.canBomb,
      },
      grandTichuDecisions: snapshot.grandTichuDecisions,
      schupfCompletedPlayers: snapshot.schupfCompletedPlayers,
      schupfReceipts: {_humanId: snapshot.schupfReceipts},
    );
  }

  @override
  Widget build(final BuildContext context) {
    final snapshot = _snapshot;
    final scoreState = snapshot?.scoreState;
    final playerRoundPoints =
        scoreState?.playerRoundPoints ?? const <String, int>{};
    final finishOrder = scoreState?.finishOrder ?? const <String>[];
    final isRoundComplete = scoreState?.roundComplete ?? false;
    final isGameComplete = scoreState?.gameComplete ?? false;
    int roundPointsFor(final String playerId) =>
        playerRoundPoints[playerId] ?? 0;
    int? finishPositionFor(final String playerId) {
      final index = finishOrder.indexOf(playerId);
      return index == -1 ? null : index + 1;
    }

    bool isFinished(final String playerId) {
      final cardsLeft = snapshot?.opponentCardCounts[playerId];
      return (cardsLeft != null && cardsLeft == 0) ||
          finishPositionFor(playerId) != null;
    }

    final displayHumanScore = roundPointsFor(_humanId);
    final displayPartnerScore = roundPointsFor('player-2');
    final displayLeftScore = roundPointsFor('player-3');
    final displayRightScore = roundPointsFor('player-1');
    final currentPlayerId = snapshot?.currentPlayerId;
    bool isCurrentTurn(final String playerId) => currentPlayerId == playerId;
    final isLocalPlayerTurn = isCurrentTurn(_humanId);
    final phase = snapshot?.phase;

    // ── Phase: schupf ──────────────────────────────────────────────────
    final isSchupfActive =
        snapshot != null &&
        phase == GamePhase.schupf &&
        (!snapshot.schupfCompletedPlayers.contains(_humanId) ||
            (!_isSelfManual &&
                snapshot.pendingOpponentPlayerId == _humanId &&
                snapshot.pendingOpponentCards.length == 3));
    final hasSchupfReceipts =
        !_schupfAckPending &&
        snapshot != null &&
        snapshot.schupfReceipts.isNotEmpty;

    // ── Phase: play ────────────────────────────────────────────────────
    final isPlayPhase = phase == GamePhase.play;
    final pendingReceipts =
        _schupfAckPending ||
        (snapshot != null && snapshot.schupfReceipts.isNotEmpty);
    final showPoints = isPlayPhase && !pendingReceipts;
    final showTurnIndicators = isPlayPhase && !pendingReceipts;
    final showTurnActions = isPlayPhase && !pendingReceipts;
    final showBomb =
        _isSelfManual && showTurnActions && (snapshot?.hasBombInHand ?? false);
    final canPlayAny = snapshot != null && _canPlayAny(snapshot);
    final canPass = snapshot != null && _canPass(snapshot);
    final passPreferred =
        _isSelfManual &&
        showTurnActions &&
        isLocalPlayerTurn &&
        !(snapshot?.opponentAwaitingConfirmation ?? false) &&
        canPass &&
        !canPlayAny;
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
      return '$targetName receives dragon';
    }();
    final centerArea =
        TrickDisplay(
          cards: _trickCards,
          currentWinnerLabel: trickLabel,
          dragonGiveLabel: dragonLabel,
          activeWish: snapshot?.activeWish ?? CardFace.none,
          trickPoints: snapshot?.trickPoints ?? 0,
          showTrickPoints: isPlayPhase && !pendingReceipts,
        ).withBombOverlay(
          showOverlay: _showBombOverlay,
          slide: _bombSlide,
          scale: _bombScale,
        );
    final showOpponentPendingCards = isPlayPhase;
    final humanTichuCall = tichuCalls['player-0'];
    final humanTichu =
        humanTichuCall == TichuCall.tichu ||
        humanTichuCall == TichuCall.grandTichu;
    final humanGrandTichu = humanTichuCall == TichuCall.grandTichu;
    final showGrandTichuDecision =
        snapshot != null && _shouldShowGrandTichuDecision(snapshot);
    final winningTeam = scoreState?.winningTeam;
    final showMatchPanel = isGameComplete && winningTeam != null;
    final handArea = PlayerHandArea(
      hand: _hand,
      selectedIndexes: _selectedIndexes,
      onCardTap: _toggleSelect,
      isActive: showTurnIndicators && isCurrentTurn(_humanId),
      isFinished: isFinished(_humanId),
      finishPosition: finishPositionFor(_humanId),
      showPoints: showPoints,
      humanScore: displayHumanScore,
      humanTichu: humanTichu,
      humanGrandTichu: humanGrandTichu,
      isSelfManual: _isSelfManual,
      isSchupfActive: isSchupfActive,
      hasSchupfReceipts: hasSchupfReceipts,
      schupfToLeft: _schupfToLeft,
      schupfToPartner: _schupfToPartner,
      schupfToRight: _schupfToRight,
      schupfSentCards: _schupfSentCards,
      schupfReceipts: snapshot?.schupfReceipts ?? const [],
      schupfAckPending: _schupfAckPending,
      schupfCursorIndex: _schupfCursorIndex,
      onSetSchupfSlot: _setSchupfSlot,
      onClearSchupfSlot: _clearSchupfSlot,
      onSubmitSchupf: _submitSchupf,
      onAcknowledgeSchupf: _acknowledgeSchupfReceipts,
      showMatchEndBanner: showMatchPanel,
      winningTeam: winningTeam,
      onMatchContinue: () => Navigator.of(context).pop(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tichu'),
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
        onKeyEvent: (final node, final event) => handleDirectionalEnterKeyEvent(
          event,
          onEnter: _handleShortcutEnter,
          onLeft: _handleShortcutLeft,
          onRight: _handleShortcutRight,
        ),
        child: SafeArea(
          child: GameBoard(
            reserveTopPendingSlot: showOpponentPendingCards,
            reserveSidePendingSlots: showOpponentPendingCards,
            topOpponent: _buildOpponent(
              playerId: 'player-2',
              name: 'Opponent 2',
              alignment: Axis.horizontal,
              icon: Icons.psychology_alt,
              snapshot: snapshot,
              tichuCalls: tichuCalls,
              showTurnIndicators: showTurnIndicators,
              showPoints: showPoints,
              teamScore: displayPartnerScore,
            ),
            topPendingSlot: _buildPendingSlot(
              playerId: 'player-2',
              showPending: showOpponentPendingCards,
              alignment: Alignment.bottomCenter,
            ),
            leftOpponent: _buildOpponent(
              playerId: 'player-3',
              name: 'Opponent 3',
              alignment: Axis.vertical,
              icon: Icons.memory,
              snapshot: snapshot,
              tichuCalls: tichuCalls,
              showTurnIndicators: showTurnIndicators,
              showPoints: showPoints,
              teamScore: displayLeftScore,
            ),
            leftPendingSlot: _buildPendingSlot(
              playerId: 'player-3',
              showPending: showOpponentPendingCards,
              alignment: Alignment.bottomRight,
            ),
            rightPendingSlot: _buildPendingSlot(
              playerId: 'player-1',
              showPending: showOpponentPendingCards,
              alignment: Alignment.bottomLeft,
            ),
            rightOpponent: _buildOpponent(
              playerId: 'player-1',
              name: 'Opponent 1',
              alignment: Axis.vertical,
              icon: Icons.smart_toy_outlined,
              snapshot: snapshot,
              tichuCalls: tichuCalls,
              showTurnIndicators: showTurnIndicators,
              showPoints: showPoints,
              teamScore: displayRightScore,
            ),
            trickArea: centerArea,
            handArea: handArea,
            actionBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showGrandTichuDecision)
                  GrandTichuBanner(
                    selectNo: _grandTichuSelectNo,
                    isPending: _grandTichuDialogOpen,
                    onDecision: (final call) =>
                        unawaited(_submitGrandTichuDecision(call)),
                    onToggle: (final selectNo) {
                      setState(() {
                        _grandTichuSelectNo = selectNo;
                      });
                    },
                  ),
                ActionBar(
                  showTurnActions: showTurnActions,
                  showBomb: showBomb,
                  isPlayEnabled:
                      _isSelfManual &&
                      snapshot != null &&
                      _canPlaySelected(snapshot) &&
                      !pendingReceipts,
                  isBombEnabled:
                      _isSelfManual &&
                      snapshot != null &&
                      snapshot.canBomb &&
                      !pendingReceipts,
                  isPassEnabled:
                      _isSelfManual &&
                      isPlayPhase &&
                      !pendingReceipts &&
                      canPass,
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
                      !showGrandTichuDecision &&
                      ((snapshot != null && phase != GamePhase.play) ||
                          (snapshot?.canCallTichu ?? false)) &&
                      !humanTichu,
                  onPlay: _playSelected,
                  onBomb: _playBomb,
                  onPass: _pass,
                  onSchupf: _submitSchupf,
                  onDeclareTichu: _declareTichu,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PlayerType _toPlayerType(final PlayerControlMode? mode) {
    if (mode == PlayerControlMode.ai) {
      return PlayerType.automated;
    }
    return PlayerType.human;
  }

  OpponentDisplay _buildOpponent({
    required final String playerId,
    required final String name,
    required final Axis alignment,
    required final IconData icon,
    required final PlayerSnapshot? snapshot,
    required final Map<String, TichuCall> tichuCalls,
    required final bool showTurnIndicators,
    required final bool showPoints,
    required final int teamScore,
  }) {
    final cardCount = snapshot?.opponentCardCounts[playerId] ?? 0;
    final finishOrder = snapshot?.scoreState.finishOrder ?? const <String>[];
    final finishIndex = finishOrder.indexOf(playerId);
    final finishPosition = finishIndex == -1 ? null : finishIndex + 1;
    final cardsLeft = snapshot?.opponentCardCounts[playerId];
    final isFinished =
        (cardsLeft != null && cardsLeft == 0) || finishPosition != null;
    final call = tichuCalls[playerId];

    return OpponentDisplay(
      name: name,
      cardCount: cardCount,
      isActive: showTurnIndicators && snapshot?.currentPlayerId == playerId,
      isFinished: isFinished,
      tichuDeclared: call == TichuCall.tichu || call == TichuCall.grandTichu,
      grandTichuDeclared: call == TichuCall.grandTichu,
      finishPosition: finishPosition,
      alignment: alignment,
      icon: icon,
      teamScore: teamScore,
      showPoints: showPoints,
    );
  }

  Widget _buildPendingSlot({
    required final String playerId,
    required final bool showPending,
    required final Alignment alignment,
  }) {
    final isActive = showPending && _pendingOpponentPlayerId == playerId;
    return PendingPlaySlot(
      cards: isActive ? _pendingOpponentCards : const [],
      isPassed: isActive && _pendingOpponentPass,
      alignment: alignment,
    );
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
      unawaited(_submitGrandTichuDecision(!_grandTichuSelectNo));
      return;
    }

    if (_trySchupfCursorAssign(snapshot)) return;

    // Acknowledge schupf receipts with Enter.
    if (snapshot.schupfReceipts.isNotEmpty && !_schupfAckPending) {
      unawaited(_acknowledgeSchupfReceipts());
      return;
    }

    if (!_isSelfManual || snapshot.phase != GamePhase.play) {
      return;
    }
    final pendingReceipts =
        _schupfAckPending || snapshot.schupfReceipts.isNotEmpty;
    final canPlay = !pendingReceipts && _canPlaySelected(snapshot);
    if (!canPlay) return;
    unawaited(_playSelected());
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

    _moveSchupfCursor(snapshot, -1);
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

    _moveSchupfCursor(snapshot, 1);
  }

  /// Returns the list of hand cards not yet assigned to a schupf slot,
  /// or `null` if schupf cursor navigation is not applicable.
  List<Card>? _schupfAvailableCards(final PlayerSnapshot snapshot) {
    final isSchupfActive =
        snapshot.phase == GamePhase.schupf &&
        !snapshot.schupfCompletedPlayers.contains(_humanId);
    if (!isSchupfActive) return null;
    if (!_hasKeyboardForSchupf) return null;

    final canSubmit =
        _schupfToLeft != null &&
        _schupfToPartner != null &&
        _schupfToRight != null;
    if (canSubmit) return null;

    final selectedCards = <Card>{
      ...[_schupfToLeft, _schupfToPartner, _schupfToRight].whereType<Card>(),
    };
    final available = _hand
        .where((final c) => !selectedCards.contains(c))
        .toList();
    return available.isEmpty ? null : available;
  }

  /// Assigns the card under the schupf cursor to the next empty slot.
  /// Returns `true` if the event was handled.
  bool _trySchupfCursorAssign(final PlayerSnapshot snapshot) {
    final isSchupfActive =
        snapshot.phase == GamePhase.schupf &&
        !snapshot.schupfCompletedPlayers.contains(_humanId);
    if (!isSchupfActive) return false;
    if (!_hasKeyboardForSchupf) return false;

    final canSubmit =
        _schupfToLeft != null &&
        _schupfToPartner != null &&
        _schupfToRight != null;
    if (canSubmit) {
      unawaited(_submitSchupf());
      return true;
    }

    final available = _schupfAvailableCards(snapshot);
    if (available == null) return true;

    final cursor = (_schupfCursorIndex ?? (available.length - 1)).clamp(
      0,
      available.length - 1,
    );
    final card = available[cursor];
    if (_schupfToRight == null) {
      _setSchupfSlot(SchupfSlot.right, card);
    } else if (_schupfToPartner == null) {
      _setSchupfSlot(SchupfSlot.partner, card);
    } else if (_schupfToLeft == null) {
      _setSchupfSlot(SchupfSlot.left, card);
    }
    return true;
  }

  /// Moves the schupf cursor by [delta] (-1 = left, +1 = right).
  void _moveSchupfCursor(final PlayerSnapshot snapshot, final int delta) {
    final available = _schupfAvailableCards(snapshot);
    if (available == null) return;

    final cursor = _schupfCursorIndex ?? (available.length - 1);
    setState(() {
      _schupfCursorIndex = (cursor + delta).clamp(0, available.length - 1);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    final gameId = _gameId;
    if (gameId != null) {
      unawaited(_backend.disposeGame(gameId));
    }
    _autoConfirmTimer?.cancel();
    _bombController.dispose();
    _schupfFocusNode.dispose();
    super.dispose();
  }

  void _setSchupfSlot(final SchupfSlot slot, final Card card) {
    setState(() {
      if (_schupfToLeft == card) _schupfToLeft = null;
      if (_schupfToPartner == card) _schupfToPartner = null;
      if (_schupfToRight == card) _schupfToRight = null;

      switch (slot) {
        case SchupfSlot.left:
          _schupfToLeft = card;
        case SchupfSlot.partner:
          _schupfToPartner = card;
        case SchupfSlot.right:
          _schupfToRight = card;
      }
      if (_hasKeyboardForSchupf) {
        _syncSchupfCursor(defaultToRightMost: true);
      } else {
        _schupfCursorIndex = null;
      }
    });
  }

  void _clearSchupfSlot(final SchupfSlot slot) {
    setState(() {
      switch (slot) {
        case SchupfSlot.left:
          _schupfToLeft = null;
        case SchupfSlot.partner:
          _schupfToPartner = null;
        case SchupfSlot.right:
          _schupfToRight = null;
      }
      if (_hasKeyboardForSchupf) {
        _syncSchupfCursor(defaultToRightMost: true);
      } else {
        _schupfCursorIndex = null;
      }
    });
  }

  void _syncSchupfCursor({required final bool defaultToRightMost}) {
    if (!_hasKeyboardForSchupf) {
      _schupfCursorIndex = null;
      return;
    }
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
    final available = _hand
        .where((final c) => !selectedCards.contains(c))
        .length;
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

  bool get _hasKeyboardForSchupf {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery != null) {
      final shortestSide = math.min(
        mediaQuery.size.width,
        mediaQuery.size.height,
      );
      if (shortestSide < 600) {
        return false;
      }
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }
}
