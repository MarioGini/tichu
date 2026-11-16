import 'package:material_ui/material_ui.dart';

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
    const shape = StadiumBorder();
    const padding = EdgeInsets.symmetric(horizontal: 16);
    const minSize = Size(0, 42);
    final neutralButtonStyle = OutlinedButton.styleFrom(
      foregroundColor: colorScheme.onSurface,
      side: const BorderSide(color: Colors.white24),
      backgroundColor: Colors.black.withValues(alpha: 0.28),
      shape: shape,
      padding: padding,
      minimumSize: minSize,
    );

    final buttons = <Widget>[
      if (showTurnActions) ...[
        if (showBomb)
          OutlinedButton.icon(
            onPressed: isBombEnabled ? onBomb : null,
            icon: const Icon(Icons.bolt, size: 18),
            style: neutralButtonStyle.copyWith(
              foregroundColor: WidgetStateProperty.resolveWith(
                (final states) => states.contains(WidgetState.disabled)
                    ? Colors.white38
                    : Colors.deepOrangeAccent.shade100,
              ),
            ),
            label: const Text('Bomb'),
          ),
        if (isPassPreferred)
          ElevatedButton.icon(
            onPressed: isPassEnabled ? onPass : null,
            icon: const Icon(Icons.not_interested, size: 18),
            style: ElevatedButton.styleFrom(
              shape: shape,
              padding: padding,
              minimumSize: minSize,
            ),
            label: const Text('Pass'),
          )
        else
          OutlinedButton.icon(
            onPressed: isPassEnabled ? onPass : null,
            icon: const Icon(Icons.not_interested, size: 18),
            style: neutralButtonStyle,
            label: const Text('Pass'),
          ),
        FilledButton.icon(
          onPressed: isPlayEnabled ? onPlay : null,
          icon: const Icon(Icons.check_circle, size: 18),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.secondary,
            foregroundColor: Colors.black87,
            disabledBackgroundColor: Colors.black.withValues(alpha: 0.28),
            disabledForegroundColor: Colors.white38,
            shape: shape,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            minimumSize: minSize,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          label: const Text('PLAY'),
        ),
        if (showSchupf)
          ElevatedButton.icon(
            onPressed: isSchupfEnabled ? onSchupf : null,
            icon: const Icon(Icons.swap_horiz, size: 18),
            style: ElevatedButton.styleFrom(
              shape: shape,
              padding: padding,
              minimumSize: minSize,
            ),
            label: Text(schupfLabel),
          ),
      ],
      if (showDeclareTichu)
        OutlinedButton.icon(
          onPressed: onDeclareTichu,
          icon: const Icon(Icons.local_fire_department, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.secondary,
            side: BorderSide(
              color: colorScheme.secondary.withValues(alpha: 0.6),
            ),
            backgroundColor: colorScheme.secondary.withValues(alpha: 0.14),
            shape: shape,
            padding: padding,
            minimumSize: minSize,
          ),
          label: const Text('Tichu'),
        ),
    ];

    if (buttons.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                buttons[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
