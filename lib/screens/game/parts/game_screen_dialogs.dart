part of '../game_screen.dart';

mixin _GameScreenDialogs on _GameScreenBindings {
  void _maybeShowRoundCompleteDialog(final PlayerSnapshot snapshot) {
    final scoreState = snapshot.scoreState;
    if (!scoreState.roundComplete) return;
    if (scoreState.roundNumber <= _lastDialogRoundNumber) return;

    _lastDialogRoundNumber = scoreState.roundNumber;
    _roundCompleteAcknowledged = false;
    final tichuSuccessMessage = _buildTichuSuccessMessage(snapshot);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (tichuSuccessMessage != null) {
        await _showTichuSuccessBeforeSummary(tichuSuccessMessage);
        if (!mounted) return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (final context) => RoundSummaryScreen(
            scoreState: scoreState,
            onBackHome: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            onStartNextRound: scoreState.gameComplete
                ? null
                : () async {
                    setState(() {
                      _roundCompleteAcknowledged = true;
                    });
                    await _startRound();
                  },
          ),
        ),
      );
    });
  }

  Future<void> _showTichuSuccessBeforeSummary(final String message) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder:
            (final context, final animation, final secondaryAnimation) =>
                _PreRoundTichuCelebration(message: message),
      ),
    );
  }

  String? _buildTichuSuccessMessage(final PlayerSnapshot snapshot) {
    final finishOrder = snapshot.scoreState.finishOrder;
    if (finishOrder.isEmpty) return null;

    final winningPlayerId = finishOrder.first;
    final winningTichuCall = snapshot.scoreState.tichuCalls[winningPlayerId];
    if (winningTichuCall == null || winningTichuCall == TichuCall.none) {
      return null;
    }

    var winningPlayerName = 'Unknown';
    for (final player in snapshot.players) {
      if (player.id == winningPlayerId) {
        winningPlayerName = player.name;
        break;
      }
    }

    final callLabel = winningTichuCall == TichuCall.grandTichu
        ? 'Grand Tichu'
        : 'Tichu';
    return '$winningPlayerName successfully called $callLabel!';
  }

  void _maybeShowDragonGiveDialog(final PlayerSnapshot snapshot) {
    if (!_isSelfManual) return;
    if (_dragonGiveDialogOpen) return;
    if (snapshot.pendingDragonGiveBy != _humanId) return;
    if (snapshot.pendingDragonGiveTargets.isEmpty) return;
    if (_gameId == null) return;

    _dragonGiveDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final targetIds = _orderDragonGiveTargetsForDisplay(snapshot);
      final selectedTarget = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (final context) => AlertDialog(
          title: const Text('Who receives the dragon?'),
          actionsAlignment: MainAxisAlignment.center,
          actions: targetIds.map((final targetId) {
            final name = snapshot.players
                .firstWhere((final player) => player.id == targetId)
                .name;
            return TextButton(
              onPressed: () => Navigator.of(context).pop(targetId),
              child: Text(name),
            );
          }).toList(),
        ),
      );

      _dragonGiveDialogOpen = false;
      if (!mounted) return;
      if (selectedTarget == null) return;
      try {
        await _backend.submitAction(
          _gameId!,
          GiveDragonAction(playerId: _humanId, targetPlayerId: selectedTarget),
        );
      } on Object catch (error) {
        _showSnack(error.toString());
      }
    });
  }

  List<String> _orderDragonGiveTargetsForDisplay(
    final PlayerSnapshot snapshot,
  ) {
    final targetIds = List<String>.from(snapshot.pendingDragonGiveTargets);
    final seatById = {
      for (final player in snapshot.players) player.id: player.seat,
    };
    final humanSeat = seatById[_humanId];
    final playerCount = snapshot.players.length;
    if (humanSeat == null || playerCount <= 0) {
      return targetIds;
    }

    int displayPriority(final String playerId) {
      final seat = seatById[playerId];
      if (seat == null) return 3;
      final relativeSeat = (seat - humanSeat + playerCount) % playerCount;
      if (relativeSeat == playerCount - 1) return 0;
      if (relativeSeat == 1) return 1;
      return 2;
    }

    targetIds.sort((final a, final b) {
      final priorityComparison = displayPriority(
        a,
      ).compareTo(displayPriority(b));
      if (priorityComparison != 0) {
        return priorityComparison;
      }
      final seatA = seatById[a] ?? playerCount;
      final seatB = seatById[b] ?? playerCount;
      return seatA.compareTo(seatB);
    });

    return targetIds;
  }

  bool _shouldShowGrandTichuDecision(final PlayerSnapshot snapshot) {
    if (!_isSelfManual) return false;
    if (snapshot.phase != GamePhase.grandTichu) return false;
    if (snapshot.currentPlayerId != _humanId) return false;
    if (snapshot.grandTichuDecisions.containsKey(_humanId)) return false;
    final humanCall = snapshot.scoreState.tichuCalls[_humanId];
    if (humanCall != null && humanCall != TichuCall.none) return false;
    return true;
  }

  @override
  Future<CardFace?> _promptWish({final CardFace? defaultWish}) async {
    if (_wishDialogOpen) return null;
    if (!mounted) return null;

    _wishDialogOpen = true;

    final wishChoices = <CardFace>[
      CardFace.none,
      ...CardFace.values.where(isWishableFace),
    ];

    String labelFor(final CardFace face) {
      switch (face) {
        case CardFace.none:
          return 'No wish';
        case CardFace.ten:
          return '10';
        case CardFace.jack:
          return 'J';
        case CardFace.queen:
          return 'Q';
        case CardFace.king:
          return 'K';
        case CardFace.ace:
          return 'A';
        case CardFace.mahJong:
        case CardFace.two:
        case CardFace.three:
        case CardFace.four:
        case CardFace.five:
        case CardFace.six:
        case CardFace.seven:
        case CardFace.eight:
        case CardFace.nine:
        case CardFace.dragon:
        case CardFace.phoenix:
        case CardFace.dog:
          return Card.getValue(face).toInt().toString();
      }
    }

    final initialChoice =
        (defaultWish != null && wishChoices.contains(defaultWish))
        ? defaultWish
        : CardFace.none;

    final selection = await showDialog<CardFace>(
      context: context,
      barrierDismissible: false,
      builder: (final context) {
        var selected = initialChoice;
        return StatefulBuilder(
          builder: (final context, final setState) => Focus(
            autofocus: true,
            onKeyEvent: (final node, final event) =>
                handleDirectionalEnterKeyEvent(
                  event,
                  onEnter: () => Navigator.of(context).pop(selected),
                  onLeft: () {},
                  onRight: () {},
                ),
            child: AlertDialog(
              title: const Text('Declare a wish'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wish: ${labelFor(selected)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: wishChoices.map((final face) {
                        final isSelected = face == selected;
                        return ChoiceChip(
                          label: Text(labelFor(face)),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              selected = face;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(selected),
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ),
        );
      },
    );

    _wishDialogOpen = false;
    return selection;
  }

  Future<void> _submitGrandTichuDecision(final bool call) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    if (_grandTichuDialogOpen) return;
    _grandTichuDialogOpen = true;
    try {
      await _backend.submitAction(
        snapshot.gameId,
        GrandTichuDecisionAction(playerId: _humanId, call: call),
      );
    } on Object catch (error) {
      _showSnack(error.toString());
    } finally {
      _grandTichuDialogOpen = false;
    }
  }

  Future<void> _submitSchupf() async {
    if (!_isSelfManual) return;
    final snapshot = _snapshot;
    if (snapshot == null) return;
    if (snapshot.phase != GamePhase.schupf) return;
    if (snapshot.schupfCompletedPlayers.contains(_humanId)) return;
    if (_schupfToLeft == null ||
        _schupfToPartner == null ||
        _schupfToRight == null) {
      _showSnack('Pick one card for each player before sending.');
      return;
    }

    final wishDefault = defaultWishFaceFromSchupf(
      toLeft: _schupfToLeft,
      toPartner: _schupfToPartner,
      toRight: _schupfToRight,
    );

    try {
      await _backend.submitAction(
        snapshot.gameId,
        SchupfAction(
          playerId: _humanId,
          toLeft: _schupfToLeft!,
          toPartner: _schupfToPartner!,
          toRight: _schupfToRight!,
        ),
      );
      setState(() {
        _schupfSentCards = <Card>[
          _schupfToLeft!,
          _schupfToPartner!,
          _schupfToRight!,
        ];
        _defaultWishFaceFromSchupf = wishDefault;
        _defaultWishRoundNumber = snapshot.scoreState.roundNumber;
        _selectedIndexes.clear();
        _schupfToLeft = null;
        _schupfToPartner = null;
        _schupfToRight = null;
      });
    } on Object catch (error) {
      _showSnack(error.toString());
    }
  }
}

class _PreRoundTichuCelebration extends StatefulWidget {
  const _PreRoundTichuCelebration({required this.message});

  final String message;

  @override
  State<_PreRoundTichuCelebration> createState() =>
      _PreRoundTichuCelebrationState();
}

class _PreRoundTichuCelebrationState extends State<_PreRoundTichuCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _slide = Tween<Offset>(begin: const Offset(0, -1.6), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeInCubic,
            reverseCurve: Curves.easeIn,
          ),
        );
    _scale = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );
    unawaited(_runSequence());
  }

  Future<void> _runSequence() async {
    await _controller.forward();
    await Future<void>.delayed(const Duration(milliseconds: 1700));
    if (!mounted) return;
    await _controller.reverse();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) => Material(
    color: Colors.transparent,
    child: SafeArea(
      child: Center(
        child: IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EventSlamOverlay(
                slide: _slide,
                scale: _scale,
                icon: Icons.emoji_events,
                label: 'TICHU',
              ),
              const SizedBox(height: 6),
              Text(
                widget.message,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
