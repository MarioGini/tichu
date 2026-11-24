import 'package:material_ui/material_ui.dart';
import 'package:tichu/screens/scoreboard/scoreboard_colors.dart';

/// Team names and target score chosen for a scoreboard match.
class ScoreboardSetupResult {
  const ScoreboardSetupResult({
    required this.teamNames,
    required this.targetScore,
  });

  final List<String> teamNames;
  final int targetScore;
}

/// Form for a new scoreboard match (or for renaming teams mid-match).
class ScoreboardSetupForm extends StatefulWidget {
  const ScoreboardSetupForm({
    super.key,
    this.initialTeamNames = const ['Team A', 'Team B'],
    this.initialTargetScore = 1000,
    required this.submitLabel,
    required this.onSubmit,
  });

  final List<String> initialTeamNames;
  final int initialTargetScore;
  final String submitLabel;
  final ValueChanged<ScoreboardSetupResult> onSubmit;

  @override
  State<ScoreboardSetupForm> createState() => _ScoreboardSetupFormState();
}

class _ScoreboardSetupFormState extends State<ScoreboardSetupForm> {
  static const _targets = [500, 1000, 1500, 2000];

  late final List<TextEditingController> _names = [
    for (final n in widget.initialTeamNames) TextEditingController(text: n),
  ];
  late int _target = widget.initialTargetScore;

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final names = List.generate(2, (final i) {
      final name = _names[i].text.trim();
      return name.isEmpty ? 'Team ${String.fromCharCode(65 + i)}' : name;
    });
    widget.onSubmit(
      ScoreboardSetupResult(teamNames: names, targetScore: _target),
    );
  }

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScoreboardPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ScoreboardSectionTitle('Teams'),
              for (final team in const [0, 1]) ...[
                if (team == 1) const SizedBox(height: 10),
                TextField(
                  controller: _names[team],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: team == 0
                      ? TextInputAction.next
                      : TextInputAction.done,
                  maxLength: 24,
                  decoration: InputDecoration(
                    labelText: team == 0 ? 'Team A' : 'Team B',
                    hintText: team == 0 ? 'e.g. Anna & Ben' : 'e.g. Cleo & Dan',
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.2),
                    prefixIcon: Icon(
                      Icons.group_outlined,
                      color: scoreboardTeamColors[team],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        ScoreboardPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ScoreboardSectionTitle('Play to'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in {..._targets, _target}.toList()..sort())
                    ChoiceChip(
                      label: Text('$t'),
                      selected: t == _target,
                      onSelected: (_) => setState(() => _target = t),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.secondary,
            foregroundColor: Colors.black87,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(widget.submitLabel),
        ),
      ],
    );
  }
}
