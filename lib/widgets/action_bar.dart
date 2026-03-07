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
    this.schupfLabel = 'Schupf',
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
  final String schupfLabel;
  final VoidCallback onPlay;
  final VoidCallback onBomb;
  final VoidCallback onPass;
  final VoidCallback onSchupf;
  final VoidCallback onDeclareTichu;

  @override
  Widget build(final BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final neutralButtonStyle = OutlinedButton.styleFrom(
      foregroundColor: colorScheme.onSurface,
      side: BorderSide.none,
      backgroundColor: colorScheme.surface.withValues(alpha: 0.2),
    );

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (final context, final constraints) {
          final availH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.of(context).size.height;
          // Proportional scaling from constraints, not screen size.
          final t = ((availH - 400) / 400).clamp(0.0, 1.0);
          final hPad = 8.0 + 4 * t;
          final vPad = 6.0 + 4 * t;
          final buttonSpacing = 6.0 + 2 * t;
          final buttonScale = ((availH - 400) / 150).clamp(0.7, 1.0);

          return Padding(
            padding: EdgeInsets.fromLTRB(hPad, 2, hPad, vPad),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: hPad,
                vertical: 4 + 2 * t,
              ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: buttonSpacing,
                    runSpacing: buttonSpacing,
                    children: [
                      if (showTurnActions) ...[
                        if (showBomb)
                          _buildButton(
                            buttonScale: buttonScale,
                            child: OutlinedButton.icon(
                              onPressed: isBombEnabled ? onBomb : null,
                              icon: const Icon(Icons.bolt),
                              style: neutralButtonStyle,
                              label: const Text('Bomb'),
                            ),
                          ),
                        if (isPassPreferred)
                          _buildButton(
                            buttonScale: buttonScale,
                            child: ElevatedButton.icon(
                              onPressed: isPassEnabled ? onPass : null,
                              icon: const Icon(Icons.not_interested),
                              label: const Text('Pass'),
                            ),
                          )
                        else
                          _buildButton(
                            buttonScale: buttonScale,
                            child: OutlinedButton.icon(
                              onPressed: isPassEnabled ? onPass : null,
                              icon: const Icon(Icons.not_interested),
                              style: neutralButtonStyle,
                              label: const Text('Pass'),
                            ),
                          ),
                        _buildButton(
                          buttonScale: buttonScale,
                          child: OutlinedButton.icon(
                            onPressed: isPlayEnabled ? onPlay : null,
                            icon: const Icon(Icons.check_circle),
                            style: neutralButtonStyle,
                            label: const Text('PLAY'),
                          ),
                        ),
                        if (showSchupf)
                          _buildButton(
                            buttonScale: buttonScale,
                            child: ElevatedButton.icon(
                              onPressed: isSchupfEnabled ? onSchupf : null,
                              icon: const Icon(Icons.swap_horiz),
                              label: Text(schupfLabel),
                            ),
                          ),
                      ],
                      if (showDeclareTichu)
                        _buildButton(
                          buttonScale: buttonScale,
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
          );
        },
      ),
    );
  }

  Widget _buildButton({
    required final double buttonScale,
    required final Widget child,
  }) {
    if (buttonScale >= 1.0) return child;
    final height = 32 + (16 * buttonScale);
    return SizedBox(
      height: height,
      child: FittedBox(child: child),
    );
  }
}
