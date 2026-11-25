import 'package:material_ui/material_ui.dart';
import 'package:tichu/game/game_session.dart';

/// Game settings, join code and who is host.
class LobbyHeader extends StatelessWidget {
  const LobbyHeader({
    super.key,
    required this.lobby,
    required this.localSeat,
    required this.onCopyJoinCode,
  });

  final GameLobbySnapshot lobby;
  final GameLobbySeatSnapshot? localSeat;
  final VoidCallback onCopyJoinCode;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 10,
    runSpacing: 6,
    children: [
      Text(
        'First to ${lobby.targetScore} • '
        '${lobby.visibility == GameLobbyVisibility.private ? "Private" : "Public"}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      if (lobby.visibility == GameLobbyVisibility.private)
        OutlinedButton.icon(
          onPressed: lobby.joinCode == null ? null : onCopyJoinCode,
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: Text('Code: ${lobby.joinCode ?? ""}'),
        ),
      Chip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(
          lobby.isLocalPlayerHost ? Icons.star : Icons.person_outline,
          size: 16,
        ),
        label: Text(
          lobby.isLocalPlayerHost ? 'You are host' : 'Waiting for host',
        ),
      ),
      Text(
        switch (localSeat) {
          null => 'Pick a seat to join the table.',
          final seat =>
            'You: ${seat.seat.isEven ? "Team 1" : "Team 2"}, seat ${seat.seat + 1}',
        },
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Colors.white70),
      ),
    ],
  );
}

/// Leave / fill with bots / ready / start buttons.
class LobbyActionBar extends StatelessWidget {
  const LobbyActionBar({
    super.key,
    required this.lobby,
    required this.localSeat,
    required this.hasOpenSeats,
    required this.supportsBots,
    required this.isBusy,
    required this.onLeave,
    required this.onFillWithBots,
    required this.onToggleReady,
    required this.onStart,
  });

  final GameLobbySnapshot lobby;
  final GameLobbySeatSnapshot? localSeat;
  final bool hasOpenSeats;
  final bool supportsBots;
  final bool isBusy;
  final VoidCallback onLeave;
  final VoidCallback onFillWithBots;
  final VoidCallback onToggleReady;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isReady = localSeat?.isReady ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        border: const Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: isBusy ? null : onLeave,
            icon: const Icon(Icons.exit_to_app),
            label: const Text('Leave'),
          ),
          if (lobby.isLocalPlayerHost && supportsBots && hasOpenSeats)
            OutlinedButton.icon(
              onPressed: isBusy ? null : onFillWithBots,
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('Fill with bots'),
            ),
          ElevatedButton.icon(
            onPressed: localSeat == null || isBusy ? null : onToggleReady,
            icon: Icon(
              isReady ? Icons.pause_circle_outline : Icons.check_circle_outline,
            ),
            label: Text(isReady ? 'Not ready' : 'Ready'),
          ),
          if (lobby.isLocalPlayerHost)
            FilledButton.icon(
              onPressed: lobby.canStart && !isBusy ? onStart : null,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.secondary,
                foregroundColor: Colors.black87,
              ),
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('Start match'),
            ),
        ],
      ),
    );
  }
}
