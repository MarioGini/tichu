part of 'observe_screen.dart';

/// Observe controls in the place of the game's action bar: the staged move
/// with its record number, speed, play / pause and Step.
class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.controller,
    required this.status,
    required this.highlight,
  });

  final ObserveController controller;
  final String status;

  /// A move is staged (status shown in amber).
  final bool highlight;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final step = controller.step;
    final error = controller.error;
    const shape = StadiumBorder();
    const minSize = Size(40, 40);
    final roundButtonStyle = IconButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.black.withValues(alpha: 0.28),
      side: const BorderSide(color: Colors.white24),
      fixedSize: minSize,
      minimumSize: minSize,
      padding: EdgeInsets.zero,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: LayoutBuilder(
        builder: (final context, final constraints) {
          final narrow = constraints.maxWidth < 380;
          final stepLabel = switch (step) {
            ObserveStep.roundOver => narrow ? 'Next' : 'Next round',
            ObserveStep.gameOver => 'Over',
            _ => 'Step',
          };
          return Row(
            children: [
              Expanded(
                child: Text(
                  error == null ? status : '$status · error: $error',
                  key: const Key('observe-status'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: error != null
                        ? Colors.redAccent
                        : highlight
                        ? Colors.amberAccent
                        : Colors.white70,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                key: const Key('observe-speed'),
                onPressed: controller.cycleSpeed,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black.withValues(alpha: 0.28),
                  side: const BorderSide(color: Colors.white24),
                  shape: shape,
                  minimumSize: const Size(44, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  controller.speedLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                key: const Key('observe-autoplay'),
                tooltip: controller.autoPlay ? 'Pause' : 'Play',
                onPressed: () => controller.setAutoPlay(!controller.autoPlay),
                style: roundButtonStyle,
                icon: Icon(
                  controller.autoPlay ? Icons.pause : Icons.play_arrow,
                ),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                key: const Key('observe-step'),
                onPressed: controller.canContinue
                    ? () => unawaited(controller.continueGame())
                    : null,
                icon: Icon(
                  step == ObserveStep.roundOver
                      ? Icons.skip_next
                      : Icons.redo_rounded,
                  size: 18,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.secondary,
                  foregroundColor: Colors.black87,
                  disabledBackgroundColor: Colors.black.withValues(alpha: 0.28),
                  disabledForegroundColor: Colors.white38,
                  shape: shape,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: minSize,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                label: Text(stepLabel),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Bottom sheet with every hand face up (seat order from the followed bot).
/// Tap a row to follow that bot.
class _AllHandsSheet extends StatelessWidget {
  const _AllHandsSheet({required this.controller});

  final ObserveController controller;

  @override
  Widget build(final BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (final context, _) {
      final snapshot = controller.snapshot;
      if (snapshot == null) return const SizedBox.shrink();
      final players = [
        for (var offset = 0; offset < 4; offset++)
          ?playerAtRelativeSeat(
            snapshot.players,
            controller.followedSeat,
            offset,
          ),
      ];
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            children: [
              for (final player in players)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SizedBox(
                    height: 68,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => controller.follow(player.seat),
                      child: _SeatPanel(
                        snapshot: snapshot,
                        player: player,
                        followed: player.seat == controller.followedSeat,
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

class _SeatPanel extends StatelessWidget {
  const _SeatPanel({
    required this.snapshot,
    required this.player,
    required this.followed,
  });

  final GameSnapshot snapshot;
  final GamePlayer player;
  final bool followed;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    final hand = [...?snapshot.hands[player.id]]..sort(compareCardsForDisplay);
    final pending =
        snapshot.opponentAwaitingConfirmation &&
        snapshot.pendingOpponentPlayerId == player.id;
    final call = snapshot.scoreState.tichuCalls[player.id] ?? TichuCall.none;
    final place = snapshot.scoreState.finishOrder.indexOf(player.id);
    final pendingCards = pending ? snapshot.pendingOpponentCards : <Card>[];
    final borderColor = pending
        ? Colors.amberAccent
        : followed
        ? Colors.white54
        : Colors.white12;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: pending ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    place >= 0
                        ? 'Out #${place + 1}'
                        : call == TichuCall.grandTichu
                        ? 'GRAND TICHU'
                        : call == TichuCall.tichu
                        ? 'TICHU'
                        : '${hand.length} cards',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: place >= 0
                          ? Colors.lightGreenAccent
                          : call != TichuCall.none
                          ? Colors.orange
                          : Colors.white60,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (final context, final constraints) {
                  final scale =
                      ((constraints.maxHeight - 10) / CardWidget.compactHeight)
                          .clamp(0.35, 0.85);
                  final width = CardWidget.compactWidth * scale;
                  final height = CardWidget.compactHeight * scale;
                  return OverlappingCardRow(
                    itemCount: hand.length,
                    cardWidth: width,
                    cardHeight: height,
                    height: constraints.maxHeight,
                    spacing: 2,
                    center: false,
                    itemBuilder: (final context, final index) {
                      final card = hand[index];
                      return CardWidget(
                        card: card,
                        compact: true,
                        scale: scale,
                        isSelected: pendingCards.any(
                          (final p) =>
                              p.face == card.face && p.color == card.color,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
