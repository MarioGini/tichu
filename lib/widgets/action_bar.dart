import 'package:flutter/material.dart';

class ActionBar extends StatelessWidget {
  const ActionBar({
    super.key,
    required this.isPlayEnabled,
    required this.isBombEnabled,
    required this.isPassEnabled,
    required this.isPassPreferred,
    required this.isSchupfEnabled,
    required this.showSchupf,
    required this.showDeclareTichu,
    required this.showStartRound,
    this.schupfLabel = 'Send Schupf',
    required this.onStartRound,
    required this.onPlay,
    required this.onBomb,
    required this.onPass,
    required this.onSchupf,
    required this.onDeclareTichu,
    required this.scoreLabel,
  });

  final bool isPlayEnabled;
  final bool isBombEnabled;
  final bool isPassEnabled;
  final bool isPassPreferred;
  final bool isSchupfEnabled;
  final bool showSchupf;
  final bool showDeclareTichu;
  final bool showStartRound;
  final String schupfLabel;
  final VoidCallback onStartRound;
  final VoidCallback onPlay;
  final VoidCallback onBomb;
  final VoidCallback onPass;
  final VoidCallback onSchupf;
  final VoidCallback onDeclareTichu;
  final String scoreLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.surface.withValues(alpha: 0.9),
            colorScheme.surface.withValues(alpha: 0.65),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 520;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: isCompact ? constraints.maxWidth : null,
                  child: Row(
                    mainAxisSize: isCompact
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.scoreboard,
                        color: colorScheme.onSurface,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          scoreLabel,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (showStartRound)
                      ElevatedButton.icon(
                        onPressed: onStartRound,
                        icon: const Icon(Icons.play_circle_fill),
                        label: const Text('Start Round'),
                      )
                    else ...[
                      OutlinedButton.icon(
                        onPressed: isBombEnabled ? onBomb : null,
                        icon: const Icon(Icons.bolt),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          side: BorderSide(
                            color: colorScheme.error.withValues(alpha: 0.7),
                          ),
                        ),
                        label: const Text('Bomb'),
                      ),
                      if (isPassPreferred)
                        ElevatedButton.icon(
                          onPressed: isPassEnabled ? onPass : null,
                          autofocus: isPassEnabled,
                          icon: const Icon(Icons.not_interested),
                          label: const Text('Pass'),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: isPassEnabled ? onPass : null,
                          icon: const Icon(Icons.not_interested),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.onSurface,
                          ),
                          label: const Text('Pass'),
                        ),
                      ElevatedButton.icon(
                        onPressed: isPlayEnabled ? onPlay : null,
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Play'),
                      ),
                      if (showSchupf)
                        ElevatedButton.icon(
                          onPressed: isSchupfEnabled ? onSchupf : null,
                          icon: const Icon(Icons.swap_horiz),
                          label: Text(schupfLabel),
                        ),
                      if (showDeclareTichu)
                        OutlinedButton.icon(
                          onPressed: onDeclareTichu,
                          icon: const Icon(Icons.local_fire_department),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.secondary,
                            side: BorderSide(color: colorScheme.secondary),
                          ),
                          label: const Text('Declare Tichu'),
                        ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
