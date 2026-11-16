import 'package:material_ui/material_ui.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';

/// The four seats, two or four per row.
class LobbySeatGrid extends StatelessWidget {
  const LobbySeatGrid({
    super.key,
    required this.seats,
    required this.localPlayerId,
    required this.onClaim,
  });

  final List<GameLobbySeatSnapshot> seats;
  final String localPlayerId;

  /// Claims an open seat; `null` while busy.
  final ValueChanged<int>? onClaim;

  @override
  Widget build(final BuildContext context) => LayoutBuilder(
    builder: (final context, final constraints) {
      final columns = constraints.maxWidth >= 560 ? 4 : 2;
      const gap = 10.0;
      final tileW = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final claim = onClaim;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final seat in seats)
            SizedBox(
              width: tileW,
              child: LobbySeatCard(
                seat: seat,
                isLocalSeat: seat.playerId == localPlayerId,
                onClaim: seat.state == GameLobbySeatState.open && claim != null
                    ? () => claim(seat.seat)
                    : null,
              ),
            ),
        ],
      );
    },
  );
}

/// One seat of the lobby table: team, occupant and a "Sit here" button.
class LobbySeatCard extends StatelessWidget {
  const LobbySeatCard({
    super.key,
    required this.seat,
    required this.isLocalSeat,
    required this.onClaim,
  });

  final GameLobbySeatSnapshot seat;
  final bool isLocalSeat;

  /// Claims this open seat; `null` disables the button.
  final VoidCallback? onClaim;

  @override
  Widget build(final BuildContext context) {
    final isOpen = seat.state == GameLobbySeatState.open;
    final teamColor = seat.seat.isEven
        ? const Color(0xFF67D99A)
        : const Color(0xFFF2C94C);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isLocalSeat ? 0.32 : 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLocalSeat ? teamColor : Colors.white12,
          width: isLocalSeat ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: teamColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${seat.seat.isEven ? "Team 1" : "Team 2"} • Seat ${seat.seat + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: Colors.white70),
                ),
              ),
              if (isLocalSeat)
                Text(
                  'YOU',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: teamColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                isOpen
                    ? Icons.event_seat_outlined
                    : seat.type == PlayerType.automated
                    ? Icons.smart_toy_outlined
                    : Icons.person,
                size: 20,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _seatPrimaryLabel(seat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _seatSecondaryLabel(seat),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white60),
          ),
          if (isOpen) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onClaim,
                child: const Text('Sit here'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _seatPrimaryLabel(final GameLobbySeatSnapshot seat) =>
      switch (seat.state) {
        GameLobbySeatState.open => 'Open seat',
        GameLobbySeatState.locked => 'Locked seat',
        GameLobbySeatState.occupied => seat.displayName ?? 'Seated player',
      };

  String _seatSecondaryLabel(final GameLobbySeatSnapshot seat) {
    if (seat.state == GameLobbySeatState.open) {
      return 'Free seat';
    }
    if (seat.state == GameLobbySeatState.locked) {
      return 'Unavailable for this lobby.';
    }
    final readyLabel = seat.isReady ? 'ready' : 'not ready';
    final typeLabel = seat.type == PlayerType.automated ? 'bot' : 'human';
    final connectionLabel = seat.isConnected ? 'connected' : 'offline';
    return '$typeLabel • $readyLabel • $connectionLabel';
  }
}
