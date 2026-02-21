import 'package:flutter/material.dart';

class ActionBar extends StatelessWidget {
  const ActionBar({
    super.key,
    required this.showTurnActions,
    required this.showBomb,
    required this.isPlayEnabled,
    required this.isBombEnabled,
    required this.isPassEnabled,
    required this.isPassPreferred,
    required this.isSchupfEnabled,
    required this.showSchupf,
    required this.showDeclareTichu,
    required this.showStartRound,
    this.schupfLabel = 'Schupf',
    required this.onStartRound,
    required this.onPlay,
    required this.onBomb,
    required this.onPass,
    required this.onSchupf,
    required this.onDeclareTichu,
  });

  final bool showTurnActions;
  final bool showBomb;
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

  @override
  Widget build(final BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 500;
    final hPad = isCompact ? 8.0 : 12.0;
    final vPad = isCompact ? 6.0 : 10.0;
    final buttonSpacing = isCompact ? 6.0 : 8.0;
    final neutralButtonStyle = OutlinedButton.styleFrom(
      foregroundColor: colorScheme.onSurface,
      side: BorderSide.none,
      backgroundColor: colorScheme.surface.withValues(alpha: 0.2),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colorScheme.surface.withValues(alpha: 0.9),
                colorScheme.surface.withValues(alpha: 0.65),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: LayoutBuilder(
            builder: (final context, final constraints) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                    else if (showTurnActions) ...[
                      if (showBomb)
                        _buildButton(
                          isCompact: isCompact,
                          child: OutlinedButton.icon(
                            onPressed: isBombEnabled ? onBomb : null,
                            icon: const Icon(Icons.bolt),
                            style: neutralButtonStyle,
                            label: const Text('Bomb'),
                          ),
                        ),
                      if (isPassPreferred)
                        _buildButton(
                          isCompact: isCompact,
                          child: ElevatedButton.icon(
                            onPressed: isPassEnabled ? onPass : null,
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
                            style: neutralButtonStyle,
                            label: const Text('Pass'),
                          ),
                        ),
                      _buildButton(
                        isCompact: isCompact,
                        child: OutlinedButton.icon(
                          onPressed: isPlayEnabled ? onPlay : null,
                          icon: const Icon(Icons.check_circle),
                          style: neutralButtonStyle,
                          label: const Text('PLAY'),
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
                    ],
                    if (showDeclareTichu)
                      _buildButton(
                        isCompact: isCompact,
                        child: OutlinedButton.icon(
                          onPressed: onDeclareTichu,
                          icon: const Icon(Icons.local_fire_department),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.secondary,
                            side: BorderSide.none,
                            backgroundColor: colorScheme.secondary.withValues(
                              alpha: 0.15,
                            ),
                          ),
                          label: const Text('Tichu'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required final bool isCompact,
    required final Widget child,
  }) {
    if (!isCompact) return child;
    return SizedBox(height: 32, child: FittedBox(child: child));
  }
}
