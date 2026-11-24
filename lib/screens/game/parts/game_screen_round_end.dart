part of '../game_screen.dart';

/// Round / match end: celebrations, then the round summary screen.
mixin _GameScreenRoundEnd on _GameScreenStateBase {
  @override
  void _maybeShowRoundCompleteDialog(PlayerSnapshot snapshot) {
    final scoreState = snapshot.scoreState;
    if (!scoreState.roundComplete) return;
    if (scoreState.roundNumber <= _lastDialogRoundNumber) return;

    _lastDialogRoundNumber = scoreState.roundNumber;
    _roundCompleteAcknowledged = false;
    final tichuSuccess = _buildTichuSuccessMessage(snapshot);
    final matchSuccess = _buildMatchSuccessMessage(
      scoreState,
      localTeam: _localTeam(snapshot),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (matchSuccess != null) {
        await _showCelebrationBeforeSummary(
          message: matchSuccess.message,
          label: 'MATCH',
          isPositive: matchSuccess.isPositive,
        );
        if (!mounted) return;
      }

      if (tichuSuccess != null) {
        await _showCelebrationBeforeSummary(
          message: tichuSuccess.message,
          label: 'TICHU',
          isPositive: tichuSuccess.isPositive,
        );
        if (!mounted) return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => RoundSummaryScreen(
            scoreState: scoreState,
            localTeam: _localTeam(snapshot),
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

  Future<void> _showCelebrationBeforeSummary({
    required String message,
    required String label,
    required bool isPositive,
  }) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) =>
            TichuCelebrationOverlay(
              message: message,
              label: label,
              isPositive: isPositive,
            ),
      ),
    );
  }

  ({String message, bool isPositive})? _buildMatchSuccessMessage(
    ScoreState scoreState, {
    required int localTeam,
  }) {
    if (!scoreState.gameComplete) return null;
    final winningTeam = scoreState.winningTeam;
    if (winningTeam == null) {
      return (message: 'The match ends in a tie!', isPositive: false);
    }
    return winningTeam == localTeam
        ? (message: 'Your team wins the match!', isPositive: true)
        : (message: 'Other team wins the match!', isPositive: false);
  }

  int _localTeam(PlayerSnapshot snapshot) {
    for (final player in snapshot.players) {
      if (player.id == _humanId) return player.seat % 2;
    }
    return 0;
  }

  ({String message, bool isPositive})? _buildTichuSuccessMessage(
    PlayerSnapshot snapshot,
  ) {
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
    final isPositive = _isOurTeamPlayer(snapshot, winningPlayerId);
    if (isPositive) {
      return (
        message: '$winningPlayerName successfully called $callLabel!',
        isPositive: true,
      );
    }
    return (
      message: '$winningPlayerName made $callLabel against your team.',
      isPositive: false,
    );
  }

  bool _isOurTeamPlayer(PlayerSnapshot snapshot, String playerId) {
    final mySeat = snapshot.players
        .firstWhere((player) => player.id == _humanId)
        .seat;
    final winnerSeat = snapshot.players
        .firstWhere((player) => player.id == playerId)
        .seat;
    return mySeat % 2 == winnerSeat % 2;
  }
}
