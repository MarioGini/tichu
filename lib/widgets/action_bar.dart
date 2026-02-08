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
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 500;
    final hPad = isCompact ? 8.0 : 12.0;
    final vPad = isCompact ? 6.0 : 10.0;
    final vBottom = isCompact ? 6.0 : 12.0;
    final buttonSpacing = isCompact ? 6.0 : 8.0;

    return Container(
      padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vBottom),
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
            final isNarrow = constraints.maxWidth < 520;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: isNarrow ? constraints.maxWidth : null,
                  child: Row(
                    mainAxisSize: isNarrow
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.scoreboard,
                        color: colorScheme.onSurface,
                        size: isCompact ? 14 : 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          scoreLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: isCompact ? 11 : null,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isCompact ? 6 : 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: buttonSpacing,
                  runSpacing: buttonSpacing,
                  children: [
                    if (showStartRound)
                      _buildButton(
                        isCompact: isCompact,
                        child: ElevatedButton.icon(
                          onPressed: onStartRound,
                          icon: const Icon(Icons.play_circle_fill),
                          label: const Text('Start Round'),
                        ),
                      )
                    else ...[
                      _buildButton(
                        isCompact: isCompact,
                        child: OutlinedButton.icon(
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
                      ),
                      if (isPassPreferred)
                        _buildButton(
                          isCompact: isCompact,
                          child: ElevatedButton.icon(
                            onPressed: isPassEnabled ? onPass : null,
                            autofocus: isPassEnabled,
                            icon: const Icon(Icons.not_interested),
                            label: const Text('Pass'),
                          ),
                        )
                      else
                        _buildButton(
                          isCompact: isCompact,
                          child: OutlinedButton.icon(
                            onPressed: isPassEnabled ? onPass : null,
                            icon: const Icon(Icons.not_interested),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.onSurface,
                            ),
                            label: const Text('Pass'),
                          ),
                        ),
                      _buildButton(
                        isCompact: isCompact,
                        child: ElevatedButton.icon(
                          onPressed: isPlayEnabled ? onPlay : null,
                          icon: const Icon(Icons.check_circle),
                          label: const Text('Play'),
                        ),
                      ),
                      if (showSchupf)
                        _buildButton(
                          isCompact: isCompact,
                          child: ElevatedButton.icon(
                            onPressed: isSchupfEnabled ? onSchupf : null,
                            icon: const Icon(Icons.swap_horiz),
                            label: Text(schupfLabel),
                          ),
                        ),
                      if (showDeclareTichu)
                        _buildButton(
                          isCompact: isCompact,
                          child: OutlinedButton.icon(
                            onPressed: onDeclareTichu,
                            icon: const Icon(Icons.local_fire_department),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.secondary,
                              side: BorderSide(color: colorScheme.secondary),
                            ),
                            label: const Text('Tichu'),
                          ),
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

  Widget _buildButton({required bool isCompact, required Widget child}) {
    if (!isCompact) return child;
    return SizedBox(height: 32, child: FittedBox(child: child));
  }
}
