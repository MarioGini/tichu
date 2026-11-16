import 'package:material_ui/material_ui.dart';

/// Title, name field and the play / create / join buttons.
class HomeStartPanel extends StatelessWidget {
  const HomeStartPanel({
    super.key,
    required this.compact,
    required this.nameController,
    required this.onNameChanged,
    required this.showSolo,
    required this.canAct,
    required this.isBusy,
    required this.onPlaySolo,
    required this.onCreate,
    required this.onJoinWithCode,
  });

  final bool compact;
  final TextEditingController nameController;
  final ValueChanged<String> onNameChanged;
  final bool showSolo;
  final bool canAct;
  final bool isBusy;
  final VoidCallback onPlaySolo;
  final VoidCallback onCreate;
  final VoidCallback onJoinWithCode;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: compact ? 0 : 12),
        Text(
          'TICHU',
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 8,
            fontSize: compact ? 30 : 40,
          ),
        ),
        Text(
          'The climbing card game for four',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white60),
        ),
        SizedBox(height: compact ? 12 : 24),
        TextField(
          controller: nameController,
          onChanged: onNameChanged,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Your name',
            prefixIcon: const Icon(Icons.person_outline),
            isDense: true,
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        SizedBox(height: compact ? 10 : 16),
        if (showSolo)
          FilledButton.icon(
            onPressed: canAct ? onPlaySolo : null,
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.secondary,
              foregroundColor: Colors.black87,
              minimumSize: Size.fromHeight(compact ? 48 : 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: isBusy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.smart_toy_outlined),
            label: const Text('Play vs AI'),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canAct ? onCreate : null,
                style: _secondaryButtonStyle,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Create game'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canAct ? onJoinWithCode : null,
                style: _secondaryButtonStyle,
                icon: const Icon(Icons.vpn_key_outlined),
                label: const Text('Join with code'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  ButtonStyle get _secondaryButtonStyle => OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    backgroundColor: Colors.black.withValues(alpha: 0.18),
    side: const BorderSide(color: Colors.white24),
    minimumSize: const Size.fromHeight(46),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );
}
