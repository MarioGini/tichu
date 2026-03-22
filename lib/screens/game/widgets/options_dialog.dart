import 'package:flutter/material.dart';

/// In-game options dialog for adjusting opponent delay, auto-pass, and sound.
class OptionsDialog extends StatefulWidget {
  const OptionsDialog({
    super.key,
    required this.aiSuggestionEnabled,
    required this.opponentDelay,
    required this.autoPassEnabled,
    required this.soundEnabled,
    required this.onAiSuggestionChanged,
    required this.onOpponentDelayChanged,
    required this.onAutoPassChanged,
    required this.onSoundChanged,
  });

  final bool aiSuggestionEnabled;
  final double opponentDelay;
  final bool autoPassEnabled;
  final bool soundEnabled;
  final ValueChanged<bool> onAiSuggestionChanged;
  final ValueChanged<double> onOpponentDelayChanged;
  final ValueChanged<bool> onAutoPassChanged;
  final ValueChanged<bool> onSoundChanged;

  @override
  State<OptionsDialog> createState() => _OptionsDialogState();
}

class _OptionsDialogState extends State<OptionsDialog> {
  late bool _aiSuggestionEnabled;
  late double _opponentDelay;
  late bool _autoPassEnabled;
  late bool _soundEnabled;

  @override
  void initState() {
    super.initState();
    _aiSuggestionEnabled = widget.aiSuggestionEnabled;
    _opponentDelay = widget.opponentDelay;
    _autoPassEnabled = widget.autoPassEnabled;
    _soundEnabled = widget.soundEnabled;
  }

  @override
  Widget build(final BuildContext context) => AlertDialog(
    title: const Text('Options'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          value: _aiSuggestionEnabled,
          onChanged: (final value) {
            setState(() {
              _aiSuggestionEnabled = value;
            });
            widget.onAiSuggestionChanged(value);
          },
          title: const Text('AI move suggestion'),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                'Opponent delay ${_opponentDelay.toStringAsFixed(0)}s',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
        Slider(
          value: _opponentDelay,
          min: 1,
          max: 5,
          divisions: 4,
          label: '${_opponentDelay.toStringAsFixed(0)}s',
          onChanged: (final value) {
            setState(() {
              _opponentDelay = value;
            });
            widget.onOpponentDelayChanged(value);
          },
        ),
        SwitchListTile(
          value: _autoPassEnabled,
          onChanged: (final value) {
            setState(() {
              _autoPassEnabled = value;
            });
            widget.onAutoPassChanged(value);
          },
          title: const Text('Auto-pass when no legal move'),
        ),
        SwitchListTile(
          value: _soundEnabled,
          onChanged: (final value) {
            setState(() {
              _soundEnabled = value;
            });
            widget.onSoundChanged(value);
          },
          title: const Text('Sound effects'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}
