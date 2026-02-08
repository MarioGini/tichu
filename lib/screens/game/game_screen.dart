import 'dart:async';

import 'package:flutter/material.dart' hide Card;

import '../../services/game_backend.dart';
import '../../services/local/local_backend.dart';
import '../../services/sound_effects.dart';
import '../../view_model/scoring/score_tracker.dart';
import '../../view_model/turn/move_generator.dart';
import '../../view_model/turn/find_turn.dart';
import '../../view_model/turn/tichu_data.dart';
import '../../view_model/turn/turn_handler.dart';
import '../../view_model/turn/utils/bomb_utils.dart';
import '../../widgets/action_bar.dart';
import '../../widgets/card_widget.dart';
import '../../widgets/hand_display.dart';
import '../../widgets/opponent_display.dart';
import '../../widgets/trick_display.dart';
import 'widgets/bomb_slam_overlay.dart';
import 'widgets/game_board.dart';

part 'parts/game_screen_actions.dart';
part 'parts/game_screen_state_bindings.dart';
part 'parts/game_screen_dialogs.dart';
part 'parts/game_screen_logic.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, GameBackend? backend, int targetScore = 1000})
    : _backend = backend,
      _targetScore = targetScore;

  final GameBackend? _backend;
  final int _targetScore;

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
  @override
  late final GameBackend _backend;
  @override
  final TurnHandler _turnHandler = TurnHandler();
  late final List<GamePlayer> _players;
  StreamSubscription<PlayerSnapshot>? _subscription;
  @override
  PlayerSnapshot? _snapshot;

  @override
  List<Card> _hand = [];
  @override
  final Set<int> _selectedIndexes = <int>{};
  List<Card> _trickCards = <Card>[];
  List<Card> _pendingAiCards = <Card>[];
  bool _pendingAiPass = false;
  String? _pendingAiLabel;
  int _activePlayerIndex = 0;
  @override
  bool _canDeclareTichu = true;
  @override
  bool _tichuDeclared = false;
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
  String? _lastAutoConfirmKey;
  @override
  String? _lastAutoPassKey;
  @override
  double _aiDelaySeconds = 2.0;
  @override
  bool _autoPassEnabled = false;
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
    _players = const [
      GamePlayer(id: 'player-0', name: 'You', seat: 0, type: PlayerType.human),
      GamePlayer(id: 'player-1', name: 'AI 1', seat: 1, type: PlayerType.ai),
      GamePlayer(
        id: 'player-2',
        name: 'AI 2 (Partner)',
        seat: 2,
        type: PlayerType.ai,
      ),
      GamePlayer(id: 'player-3', name: 'AI 3', seat: 3, type: PlayerType.ai),
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
      _activePlayerIndex = _players.indexWhere(
        (player) => player.id == snapshot.currentPlayerId,
      );
      _trickCards = List<Card>.from(snapshot.deck.turn.cards);
      _pendingAiCards = List<Card>.from(snapshot.pendingAiCards);
      _pendingAiPass = snapshot.pendingAiPass;
      final pendingAiId = snapshot.pendingAiPlayerId;
      _pendingAiLabel = pendingAiId == null
          ? null
          : snapshot.players
                .firstWhere((player) => player.id == pendingAiId)
                .name;
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
    _maybeAutoConfirmAi(snapshot);
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
    final teamOneTotal = scoreState?.teamOneTotal ?? 0;
    final teamTwoTotal = scoreState?.teamTwoTotal ?? 0;
    final isRoundComplete = scoreState?.roundComplete ?? false;
    final isGameComplete = scoreState?.gameComplete ?? false;
    final targetScore = scoreState?.targetScore ?? widget._targetScore;
    final isHumanTurn = snapshot?.currentPlayerId == _humanId;
    final awaitingAiConfirm = snapshot?.aiAwaitingConfirmation ?? false;
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
        isPlayPhase &&
        isHumanTurn &&
        !isSchupfActive &&
        !hasSchupfReceipts &&
        !awaitingAiConfirm &&
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
          pendingAiLabel: _pendingAiLabel,
          pendingAiCards: _pendingAiCards,
          pendingAiPass: _pendingAiPass,
        ).withBombOverlay(
          showOverlay: _showBombOverlay,
          slide: _bombSlide,
          scale: _bombScale,
        );
    final handArea = isSchupfActive
        ? _buildSchupfPanel()
        : hasSchupfReceipts
        ? _buildSchupfReceiptPanel(snapshot, playerNames)
        : HandDisplay(
            cards: _hand,
            selectedIndexes: _selectedIndexes,
            onCardTap: _toggleSelect,
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
            name: 'AI 2 (Partner)',
            cardCount: snapshot?.opponentCardCounts['player-2'] ?? 0,
            isActive: _activePlayerIndex == 2,
            tichuDeclared:
                tichuCalls['player-2'] == TichuCall.tichu ||
                tichuCalls['player-2'] == TichuCall.grandTichu,
            grandTichuDeclared: tichuCalls['player-2'] == TichuCall.grandTichu,
            finishPosition: null,
            alignment: Axis.horizontal,
            icon: Icons.psychology_alt,
            pendingCards: snapshot?.pendingAiPlayerId == 'player-2'
                ? _pendingAiCards
                : const [],
            pendingPass:
                snapshot?.pendingAiPlayerId == 'player-2' && _pendingAiPass,
          ),
          leftOpponent: OpponentDisplay(
            name: 'AI 1',
            cardCount: snapshot?.opponentCardCounts['player-1'] ?? 0,
            isActive: _activePlayerIndex == 1,
            tichuDeclared:
                tichuCalls['player-1'] == TichuCall.tichu ||
                tichuCalls['player-1'] == TichuCall.grandTichu,
            grandTichuDeclared: tichuCalls['player-1'] == TichuCall.grandTichu,
            finishPosition: null,
            alignment: Axis.vertical,
            icon: Icons.smart_toy_outlined,
            pendingCards: snapshot?.pendingAiPlayerId == 'player-1'
                ? _pendingAiCards
                : const [],
            pendingPass:
                snapshot?.pendingAiPlayerId == 'player-1' && _pendingAiPass,
          ),
          rightOpponent: OpponentDisplay(
            name: 'AI 3',
            cardCount: snapshot?.opponentCardCounts['player-3'] ?? 0,
            isActive: _activePlayerIndex == 3,
            tichuDeclared:
                tichuCalls['player-3'] == TichuCall.tichu ||
                tichuCalls['player-3'] == TichuCall.grandTichu,
            grandTichuDeclared: tichuCalls['player-3'] == TichuCall.grandTichu,
            finishPosition: null,
            alignment: Axis.vertical,
            icon: Icons.memory,
            pendingCards: snapshot?.pendingAiPlayerId == 'player-3'
                ? _pendingAiCards
                : const [],
            pendingPass:
                snapshot?.pendingAiPlayerId == 'player-3' && _pendingAiPass,
          ),
          trickArea: centerArea,
          handArea: handArea,
          actionBar: ActionBar(
            isPlayEnabled:
                snapshot != null &&
                _canPlaySelected(snapshot) &&
                !isSchupfActive &&
                !hasSchupfReceipts &&
                !_schupfAckPending,
            isBombEnabled:
                snapshot != null &&
                _canEnableBomb(snapshot) &&
                !isSchupfActive &&
                !hasSchupfReceipts &&
                !_schupfAckPending,
            isPassEnabled:
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
                !isRoundComplete &&
                isHumanTurn &&
                _canDeclareTichu &&
                !_tichuDeclared &&
                isPlayPhase,
            showStartRound: canStartRound,
            onStartRound: _startRound,
            onPlay: _playSelected,
            onBomb: _playBomb,
            onPass: _pass,
            onSchupf: _submitSchupf,
            onDeclareTichu: _declareTichu,
            scoreLabel:
                'Your team: $teamOneTotal — Other team: $teamTwoTotal · '
                'Target: $targetScore',
          ),
        ),
      ),
    );
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
                          'AI delay ${_aiDelaySeconds.toStringAsFixed(0)}s',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _aiDelaySeconds,
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '${_aiDelaySeconds.toStringAsFixed(0)}s',
                    onChanged: (value) {
                      setState(() {
                        _aiDelaySeconds = value;
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
        final targetHeight = maxHeight == null
            ? CardWidget.compactHeight * 0.9 + 72
            : (CardWidget.compactHeight * 0.9 + 72)
                  .clamp(120.0, maxHeight * 0.55)
                  .toDouble();

        Widget buildTarget({
          required String label,
          required Card? value,
          required VoidCallback onRemove,
          required ValueChanged<Card> onAccept,
        }) {
          return SizedBox(
            width: targetWidth,
            child: DragTarget<Card>(
              onAcceptWithDetails: (details) => onAccept(details.data),
              builder: (context, candidateData, rejectedData) {
                final isActive = candidateData.isNotEmpty;
                return GestureDetector(
                  onTap: value == null ? null : onRemove,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(6),
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: Colors.white70),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        if (value == null)
                          Icon(
                            Icons.add_circle_outline,
                            color: Colors.white38,
                            size: 28,
                          )
                        else
                          Flexible(
                            child: CardWidget(
                              card: value,
                              isSelected: false,
                              compact: true,
                              scale: 0.9,
                            ),
                          ),
                        if (value != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Tap to remove',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: Colors.white54),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
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
                  'Schupf your cards',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Drag one card to each target.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    buildTarget(
                      label: 'Left opponent',
                      value: _schupfToLeft,
                      onRemove: () => _clearSchupfSlot(_SchupfSlot.left),
                      onAccept: (card) =>
                          _setSchupfSlot(_SchupfSlot.left, card),
                    ),
                    const SizedBox(width: 12),
                    buildTarget(
                      label: 'Partner',
                      value: _schupfToPartner,
                      onRemove: () => _clearSchupfSlot(_SchupfSlot.partner),
                      onAccept: (card) =>
                          _setSchupfSlot(_SchupfSlot.partner, card),
                    ),
                    const SizedBox(width: 12),
                    buildTarget(
                      label: 'Right opponent',
                      value: _schupfToRight,
                      onRemove: () => _clearSchupfSlot(_SchupfSlot.right),
                      onAccept: (card) =>
                          _setSchupfSlot(_SchupfSlot.right, card),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Available cards',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: canSubmit ? _submitSchupf : null,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Send Schupf'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final card in available)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Draggable<Card>(
                                data: card,
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: CardWidget(
                                    card: card,
                                    isSelected: false,
                                    compact: true,
                                    scale: 0.9,
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.4,
                                  child: CardWidget(
                                    card: card,
                                    isSelected: false,
                                    compact: true,
                                    scale: 0.9,
                                  ),
                                ),
                                child: CardWidget(
                                  card: card,
                                  isSelected: false,
                                  compact: true,
                                  scale: 0.9,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSchupfReceiptPanel(
    PlayerSnapshot snapshot,
    Map<String, String> playerNames,
  ) {
    final targetWidth = CardWidget.compactWidth * 1.05;
    final receipts = snapshot.schupfReceipts;
    final receiptByDirection = {
      for (final receipt in receipts) receipt.direction: receipt,
    };

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
          height: CardWidget.compactHeight * 0.9 + 72,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                fromName,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: Colors.white54),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              if (receipt == null)
                Icon(Icons.hourglass_empty, color: Colors.white38, size: 28)
              else
                CardWidget(
                  card: receipt.card,
                  isSelected: false,
                  compact: true,
                  scale: 0.9,
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
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
          Text(
            'Review your cards before starting the round.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              buildTarget(
                label: 'Left opponent',
                receipt: receiptByDirection[SchupfDirection.left],
              ),
              const SizedBox(width: 12),
              buildTarget(
                label: 'Partner',
                receipt: receiptByDirection[SchupfDirection.partner],
              ),
              const SizedBox(width: 12),
              buildTarget(
                label: 'Right opponent',
                receipt: receiptByDirection[SchupfDirection.right],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _schupfAckPending ? null : _acknowledgeSchupfReceipts,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(_schupfAckPending ? 'Accepting…' : 'Accept schupf'),
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
