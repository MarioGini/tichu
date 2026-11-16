import 'package:material_ui/material_ui.dart';
import 'package:tichu/game/game_session.dart';

/// The list of public games, with refresh and join buttons.
class OpenGamesPanel extends StatelessWidget {
  const OpenGamesPanel({
    super.key,
    required this.publicGames,
    required this.canJoin,
    required this.onRefresh,
    required this.onJoin,
  });

  final List<GameLobbyListEntry> publicGames;
  final bool canJoin;
  final VoidCallback onRefresh;
  final ValueChanged<GameLobbyListEntry> onJoin;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 0),
            child: Row(
              children: [
                const Icon(Icons.public, size: 18, color: Colors.white70),
                const SizedBox(width: 8),
                Text('Open games', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: publicGames.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No open games right now.\nCreate one or play vs AI.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    itemCount: publicGames.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Colors.white12),
                    itemBuilder: (final context, final index) =>
                        _buildGameTile(publicGames[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameTile(final GameLobbyListEntry entry) {
    final title = entry.gameName.isNotEmpty
        ? entry.gameName
        : "${entry.hostDisplayName}'s Game";
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        child: Text('${entry.occupiedSeats}/${entry.totalSeats}'),
      ),
      title: Text(title),
      subtitle: Text(
        'Host: ${entry.hostDisplayName} • First to ${entry.targetScore}',
      ),
      trailing: FilledButton(
        onPressed: canJoin ? () => onJoin(entry) : null,
        child: const Text('Join'),
      ),
    );
  }
}
