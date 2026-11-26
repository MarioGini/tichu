part of 'observe_screen.dart';

const _teamA = Color(0xFF64B5F6);
const _teamB = Color(0xFFFFB74D);

Color _teamColor(int seat) => seat.isEven ? _teamA : _teamB;

String _teamName(int seat) => seat.isEven ? 'Team A' : 'Team B';

/// Centre panel plus one row per seat (all hands face up).
class _ObserveTable extends StatelessWidget {
  const _ObserveTable({required this.snapshot, required this.record});

  final GameSnapshot snapshot;
  final GameRecord record;

  @override
  Widget build(BuildContext context) {
    final players = [...snapshot.players]
      ..sort((a, b) => a.seat.compareTo(b.seat));
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TrickPanel(snapshot: snapshot, record: record),
          const SizedBox(height: 6),
          for (final player in players)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _SeatPanel(snapshot: snapshot, player: player),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrickPanel extends StatelessWidget {
  const _TrickPanel({required this.snapshot, required this.record});

  final GameSnapshot snapshot;
  final GameRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // deck.turn is reset when a trick is won; lastPlayedTurn is not.
    final turn = snapshot.deck.turn;
    final onTable = snapshot.lastPlayedBy != null && turn.cards.isNotEmpty;
    final pendingId = snapshot.opponentAwaitingConfirmation
        ? snapshot.pendingOpponentPlayerId
        : null;
    final next = pendingId == null
        ? null
        : '#${record.events.length + 1}  '
              '${record.nameOf(pendingId)} → ${_pendingText(snapshot)}';
    final wish = snapshot.activeWish;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  onTable
                      ? 'On table: ${record.nameOf(snapshot.lastPlayedBy)}'
                      : 'Table empty (lead)',
                  style: theme.textTheme.titleSmall,
                ),
                if (onTable)
                  Text(
                    cardLabels(turn.cards).join(' '),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (snapshot.trickPoints != 0)
                  Text('Trick: ${snapshot.trickPoints} pts'),
                if (wish != CardFace.none)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Wish: ${faceLabel(wish)}'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              next ?? _phaseText(snapshot),
              style: theme.textTheme.titleMedium?.copyWith(
                color: next == null ? Colors.white70 : Colors.amberAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _pendingText(GameSnapshot s) {
  if (s.pendingOpponentPass) return 'passes';
  if (s.pendingOpponentCards.isEmpty) return 'calls TICHU';
  return 'plays ${cardLabels(s.pendingOpponentCards).join(' ')}';
}

String _phaseText(GameSnapshot s) {
  if (s.scoreState.gameComplete) return 'Game over';
  if (s.scoreState.roundComplete) return 'Round over';
  return switch (s.phase) {
    GamePhase.grandTichu => 'Dealing — Grand Tichu decisions…',
    GamePhase.schupf => 'Schupf — bots pass cards…',
    GamePhase.play => 'Bots are thinking…',
  };
}

class _SeatPanel extends StatelessWidget {
  const _SeatPanel({required this.snapshot, required this.player});

  final GameSnapshot snapshot;
  final GamePlayer player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hand = [...?snapshot.hands[player.id]]..sort(compareCardsForDisplay);
    final pending =
        snapshot.opponentAwaitingConfirmation &&
        snapshot.pendingOpponentPlayerId == player.id;
    final isCurrent =
        snapshot.phase == GamePhase.play &&
        !snapshot.scoreState.roundComplete &&
        snapshot.currentPlayerId == player.id;
    final call = snapshot.scoreState.tichuCalls[player.id] ?? TichuCall.none;
    final place = snapshot.scoreState.finishOrder.indexOf(player.id);
    final pendingCards = pending ? snapshot.pendingOpponentCards : <Card>[];
    final borderColor = pending
        ? Colors.amberAccent
        : isCurrent
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
              width: 112,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: _teamColor(player.seat),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${_teamName(player.seat)} · ${hand.length} cards',
                    style: theme.textTheme.labelSmall,
                  ),
                  if (call != TichuCall.none)
                    Text(
                      call == TichuCall.grandTichu ? 'GRAND TICHU' : 'TICHU',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  if (place >= 0)
                    Text(
                      'Out #${place + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.lightGreenAccent,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
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
                    itemBuilder: (context, index) {
                      final card = hand[index];
                      return CardWidget(
                        card: card,
                        compact: true,
                        scale: scale,
                        isSelected: pendingCards.any(
                          (p) => p.face == card.face && p.color == card.color,
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

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.controller});

  final ObserveController controller;

  @override
  Widget build(BuildContext context) {
    final step = controller.step;
    final label = switch (step) {
      ObserveStep.move => 'Continue',
      ObserveStep.roundOver => 'Next round',
      ObserveStep.gameOver => 'Game over',
      ObserveStep.working => 'Bots are thinking…',
    };
    final error = controller.error;
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: controller.canContinue
                    ? () => unawaited(controller.continueGame())
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: Icon(
                  step == ObserveStep.roundOver
                      ? Icons.skip_next
                      : Icons.play_arrow,
                ),
                label: Text(
                  error == null ? label : '$label (error: $error)',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: controller.autoPlay,
                  onChanged: controller.setAutoPlay,
                ),
                Text('Auto', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
