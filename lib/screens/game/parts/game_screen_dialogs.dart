part of '../game_screen.dart';

mixin _GameScreenDialogs on _GameScreenBindings {
  void _maybeShowRoundCompleteDialog(PlayerSnapshot snapshot) {
    final scoreState = snapshot.scoreState;
    if (!scoreState.roundComplete) return;
    if (scoreState.roundNumber <= _lastDialogRoundNumber) return;
    final latestRound = scoreState.rounds.isEmpty
        ? null
        : scoreState.rounds.last;
    final isMatchRound = latestRound?.isMatch ?? false;

    _lastDialogRoundNumber = scoreState.roundNumber;
    _roundCompleteAcknowledged = false;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (isMatchRound) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (!mounted) return;
        await _showMatchCelebrationGateDialog();
        if (!mounted) return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          if (scoreState.gameComplete) {
            final winnerLabel = switch (scoreState.winningTeam) {
              0 => 'Your team wins!',
              1 => 'Other team wins!',
              _ => 'It\'s a tie!',
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
                  _startRound();
                },
                child: const Text('Start next round'),
              ),
            ],
          );
        },
      );
    });
  }

  Future<void> _showMatchCelebrationGateDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Match!'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.celebration, color: colorScheme.primary),
              const SizedBox(width: 10),
              const Flexible(
                child: Text('Great finish — continue to the score board.'),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScoreSummaryTable(BuildContext context, ScoreState scoreState) {
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
        (round) => TableRow(
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

  void _maybeShowDragonGiveDialog(PlayerSnapshot snapshot) {
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
        builder: (context) {
          return AlertDialog(
            title: const Text('Who receives the dragon?'),
            actionsAlignment: MainAxisAlignment.center,
            actions: targetIds.map((targetId) {
              final name = snapshot.players
                  .firstWhere((player) => player.id == targetId)
                  .name;
              return TextButton(
                onPressed: () => Navigator.of(context).pop(targetId),
                child: Text(name),
              );
            }).toList(),
          );
        },
      );

      _dragonGiveDialogOpen = false;
      if (!mounted) return;
      if (selectedTarget == null) return;
      try {
        await _backend.submitAction(
          _gameId!,
          GiveDragonAction(playerId: _humanId, targetPlayerId: selectedTarget),
        );
      } catch (error) {
        _showSnack(error.toString());
      }
    });
  }

  List<String> _orderDragonGiveTargetsForDisplay(PlayerSnapshot snapshot) {
    final targetIds = List<String>.from(snapshot.pendingDragonGiveTargets);
    final seatById = {
      for (final player in snapshot.players) player.id: player.seat,
    };
    final humanSeat = seatById[_humanId];
    final playerCount = snapshot.players.length;
    if (humanSeat == null || playerCount <= 0) {
      return targetIds;
    }

    int displayPriority(String playerId) {
      final seat = seatById[playerId];
      if (seat == null) return 3;
      final relativeSeat = (seat - humanSeat + playerCount) % playerCount;
      if (relativeSeat == playerCount - 1) return 0;
      if (relativeSeat == 1) return 1;
      return 2;
    }

    targetIds.sort((a, b) {
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

  void _maybeShowGrandTichuDialog(PlayerSnapshot snapshot) {
    if (!_isSelfManual) return;
    if (_grandTichuDialogOpen) return;
    if (snapshot.phase != GamePhase.grandTichu) return;
    if (snapshot.currentPlayerId != _humanId) return;
    if (snapshot.grandTichuDecisions.containsKey(_humanId)) return;

    _grandTichuDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final call = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Call Grand Tichu?'),
            content: const Text(
              'Decide now before receiving the remaining cards.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes'),
              ),
            ],
          );
        },
      );
      _grandTichuDialogOpen = false;
      if (!mounted || call == null) return;
      await _submitGrandTichuDecision(call);
    });
  }

  @override
  Future<CardFace?> _promptWish({CardFace? defaultWish}) async {
    if (_wishDialogOpen) return null;
    if (!mounted) return null;

    _wishDialogOpen = true;

    const wishChoices = <CardFace>[
      CardFace.none,
      CardFace.two,
      CardFace.three,
      CardFace.four,
      CardFace.five,
      CardFace.six,
      CardFace.seven,
      CardFace.eight,
      CardFace.nine,
      CardFace.ten,
      CardFace.jack,
      CardFace.queen,
      CardFace.king,
      CardFace.ace,
    ];

    String labelFor(CardFace face) {
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
        default:
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
      builder: (context) {
        CardFace selected = initialChoice;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
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
                      children: wishChoices.map((face) {
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
            );
          },
        );
      },
    );

    _wishDialogOpen = false;
    return selection;
  }

  Future<void> _submitGrandTichuDecision(bool call) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    try {
      await _backend.submitAction(
        snapshot.gameId,
        GrandTichuDecisionAction(playerId: _humanId, call: call),
      );
    } catch (error) {
      _showSnack(error.toString());
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
    } catch (error) {
      _showSnack(error.toString());
    }
  }
}

class _ScoreSummaryCell extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _ScoreSummaryCell(this.text, {this.style});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(text, style: style),
    );
  }
}

CardFace? defaultWishFaceFromSchupf({
  required Card? toLeft,
  required Card? toPartner,
  required Card? toRight,
}) {
  return toRight?.face;
}
