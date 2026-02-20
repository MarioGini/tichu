part of '../game_screen.dart';

mixin _GameScreenDialogs on _GameScreenBindings {
  void _maybeShowRoundCompleteDialog(final PlayerSnapshot snapshot) {
    final scoreState = snapshot.scoreState;
    if (!scoreState.roundComplete) return;
    if (scoreState.roundNumber <= _lastDialogRoundNumber) return;

    _lastDialogRoundNumber = scoreState.roundNumber;
    _roundCompleteAcknowledged = false;

    // In AI-self mode, auto-continue after a brief pause so the user can
    // see the scoreboard without needing to click through.
    if (!_isSelfManual && !scoreState.gameComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _roundCompleteAcknowledged = true;
        });
        unawaited(_startRound());
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (final context) {
          if (scoreState.gameComplete) {
            final winnerLabel = switch (scoreState.winningTeam) {
              0 => 'Your team wins!',
              1 => 'Other team wins!',
              _ => "It's a tie!",
            };
            return AlertDialog(
              title: const Text('Match complete'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildScoreSummaryTable(context, scoreState),
                  const SizedBox(height: 12),
                  Text('Target: ${scoreState.targetScore} points'),
                  const SizedBox(height: 12),
                  Text(
                    winnerLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Back to home'),
                ),
              ],
            );
          }
          return AlertDialog(
            title: Text('Round ${scoreState.roundNumber} complete'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_buildScoreSummaryTable(context, scoreState)],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _roundCompleteAcknowledged = true;
                  });
                  Navigator.of(context).pop();
                  unawaited(_startRound());
                },
                child: const Text('Start next round'),
              ),
            ],
          );
        },
      );
    });
  }

  Widget _buildScoreSummaryTable(final BuildContext context, final ScoreState scoreState) {
    if (scoreState.rounds.isEmpty) {
      return const Text('No scoring data yet.');
    }

    final headerStyle = Theme.of(context).textTheme.labelLarge;
    final numberStyle = Theme.of(context).textTheme.bodyMedium;

    final rows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        children: [
          _ScoreSummaryCell('Round', style: headerStyle),
          _ScoreSummaryCell('Your team', style: headerStyle),
          _ScoreSummaryCell('Other team', style: headerStyle),
        ],
      ),
      ...scoreState.rounds.map(
        (final round) => TableRow(
          children: [
            _ScoreSummaryCell('${round.roundNumber}', style: numberStyle),
            _ScoreSummaryCell('${round.teamOnePoints}', style: numberStyle),
            _ScoreSummaryCell('${round.teamTwoPoints}', style: numberStyle),
          ],
        ),
      ),
      TableRow(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        children: [
          _ScoreSummaryCell('Total', style: headerStyle),
          _ScoreSummaryCell('${scoreState.teamOneTotal}', style: headerStyle),
          _ScoreSummaryCell('${scoreState.teamTwoTotal}', style: headerStyle),
        ],
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(
          color: Theme.of(context).dividerColor,
          width: 0.5,
        ),
        children: rows,
      ),
    );
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

  List<String> _orderDragonGiveTargetsForDisplay(final PlayerSnapshot snapshot) {
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
          builder: (final context, final setState) => AlertDialog(
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

class _ScoreSummaryCell extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _ScoreSummaryCell(this.text, {this.style});

  @override
  Widget build(final BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(text, style: style),
    );
}
