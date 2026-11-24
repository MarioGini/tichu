import 'package:material_ui/material_ui.dart';
import 'package:tichu/scoreboard/scoreboard_model.dart';
import 'package:tichu/screens/scoreboard/scoreboard_colors.dart';
import 'package:tichu/widgets/game_gradient_background.dart';

/// Result of [RoundEntryScreen]: the round to save, or a request to delete
/// the round being edited.
sealed class RoundEntryResult {
  const RoundEntryResult();
}

class RoundEntrySaved extends RoundEntryResult {
  const RoundEntrySaved(this.round);
  final ScoreboardRound round;
}

class RoundEntryDeleted extends RoundEntryResult {
  const RoundEntryDeleted();
}

/// Enter one real-life round: double victory, counted card points and the
/// Tichu calls with their outcome.
class RoundEntryScreen extends StatefulWidget {
  const RoundEntryScreen({
    super.key,
    required this.teamNames,
    required this.roundNumber,
    this.initial,
  });

  final List<String> teamNames;
  final int roundNumber;

  /// The round being edited; null for a new round.
  final ScoreboardRound? initial;

  @override
  State<RoundEntryScreen> createState() => _RoundEntryScreenState();
}

class _RoundEntryScreenState extends State<RoundEntryScreen> {
  late ScoreboardRound _round = widget.initial ?? const ScoreboardRound();

  bool get _isEdit => widget.initial != null;

  void _update(final ScoreboardRound round) => setState(() => _round = round);

  void _setDoubleVictory(final int? team) {
    // The double-victory team went out first, so a call by the other team
    // has failed.
    final calls = _round.calls
        .map(
          (final c) =>
              team != null && c.team != team ? c.copyWith(success: false) : c,
        )
        .toList();
    _update(_round.copyWith(doubleVictoryTeam: () => team, calls: calls));
  }

  void _setCardPoints(final int teamA) => _update(
    _round.copyWith(
      cardPointsTeamA: teamA.clamp(
        ScoreboardRound.minCardPoints,
        ScoreboardRound.maxCardPoints,
      ),
    ),
  );

  void _addCall(final int team, final TichuCallKind kind) {
    final dv = _round.doubleVictoryTeam;
    final canSucceed =
        !_round.calls.any((final c) => c.success) && (dv == null || dv == team);
    _update(
      _round.copyWith(
        calls: [
          ..._round.calls,
          TichuCall(team: team, kind: kind, success: canSucceed),
        ],
      ),
    );
  }

  void _setCallSuccess(final int index, final bool success) {
    // Only one player goes out first: making one call fails the others.
    final calls = List.generate(_round.calls.length, (final i) {
      final call = _round.calls[i];
      if (i == index) return call.copyWith(success: success);
      return success ? call.copyWith(success: false) : call;
    });
    _update(_round.copyWith(calls: calls));
  }

  void _removeCall(final int index) =>
      _update(_round.copyWith(calls: [..._round.calls]..removeAt(index)));

  void _save() {
    if (!_round.isValid) return;
    Navigator.of(context).pop(RoundEntrySaved(_round));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (final context) => AlertDialog(
        title: Text('Delete round ${widget.roundNumber}?'),
        content: const Text('The totals are recalculated without it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && mounted) {
      Navigator.of(context).pop(const RoundEntryDeleted());
    }
  }

  @override
  Widget build(final BuildContext context) {
    final errors = _round.validate();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          _isEdit
              ? 'Edit round ${widget.roundNumber}'
              : 'Round ${widget.roundNumber}',
        ),
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete round',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: GameGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        _DoubleVictorySection(
                          teamNames: widget.teamNames,
                          value: _round.doubleVictoryTeam,
                          onChanged: _setDoubleVictory,
                        ),
                        const SizedBox(height: 12),
                        _CardPointsSection(
                          teamNames: widget.teamNames,
                          round: _round,
                          onChanged: _setCardPoints,
                        ),
                        const SizedBox(height: 12),
                        _CallsSection(
                          teamNames: widget.teamNames,
                          calls: _round.calls,
                          onAdd: _addCall,
                          onSuccessChanged: _setCallSuccess,
                          onRemove: _removeCall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _RoundSummaryBar(
                teamNames: widget.teamNames,
                round: _round,
                errors: errors,
                onSave: errors.isEmpty ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoubleVictorySection extends StatelessWidget {
  const _DoubleVictorySection({
    required this.teamNames,
    required this.value,
    required this.onChanged,
  });

  final List<String> teamNames;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(final BuildContext context) => ScoreboardPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScoreboardSectionTitle('Double victory (1-2 finish)'),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: -1, label: Text('None')),
            for (final team in const [0, 1])
              ButtonSegment(
                value: team,
                label: Text(teamNames[team], overflow: TextOverflow.ellipsis),
              ),
          ],
          selected: {value ?? -1},
          onSelectionChanged: (final s) =>
              onChanged(s.first == -1 ? null : s.first),
        ),
      ],
    ),
  );
}

class _CardPointsSection extends StatelessWidget {
  const _CardPointsSection({
    required this.teamNames,
    required this.round,
    required this.onChanged,
  });

  final List<String> teamNames;
  final ScoreboardRound round;
  final ValueChanged<int> onChanged;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    final doubleVictory = round.doubleVictoryTeam != null;
    final a = round.cardPointsFor(0);
    Widget side(final int team, final int points) => Expanded(
      child: Column(
        children: [
          Text(
            teamNames[team],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scoreboardTeamColors[team],
            ),
          ),
          Text(
            '$points',
            style: theme.textTheme.displaySmall
                ?.merge(scoreboardTabular)
                .copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
    return ScoreboardPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScoreboardSectionTitle(
            doubleVictory ? 'Card points (double victory)' : 'Card points',
          ),
          Row(
            children: [
              side(0, a),
              Text(
                ':',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white38,
                ),
              ),
              side(1, round.cardPointsFor(1)),
            ],
          ),
          if (doubleVictory)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Cards are not counted: the double victory scores 200.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
              ),
            )
          else ...[
            Slider(
              value: a.toDouble(),
              min: ScoreboardRound.minCardPoints.toDouble(),
              max: ScoreboardRound.maxCardPoints.toDouble(),
              divisions:
                  (ScoreboardRound.maxCardPoints -
                      ScoreboardRound.minCardPoints) ~/
                  5,
              label: '$a : ${100 - a}',
              activeColor: scoreboardTeamColors[0],
              inactiveColor: scoreboardTeamColors[1].withValues(alpha: 0.6),
              onChanged: (final v) => onChanged(v.round()),
            ),
            Row(
              children: [
                _StepButton(label: '−5', onTap: () => onChanged(a - 5)),
                const SizedBox(width: 6),
                _StepButton(label: '+5', onTap: () => onChanged(a + 5)),
                Expanded(
                  child: Text(
                    'Sums to 100',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white38,
                    ),
                  ),
                ),
                _StepButton(label: '−5', onTap: () => onChanged(a + 5)),
                const SizedBox(width: 6),
                _StepButton(label: '+5', onTap: () => onChanged(a - 5)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white24),
      minimumSize: const Size(44, 36),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    child: Text(label),
  );
}

class _CallsSection extends StatelessWidget {
  const _CallsSection({
    required this.teamNames,
    required this.calls,
    required this.onAdd,
    required this.onSuccessChanged,
    required this.onRemove,
  });

  final List<String> teamNames;
  final List<TichuCall> calls;
  final void Function(int team, TichuCallKind kind) onAdd;
  final void Function(int index, bool success) onSuccessChanged;
  final ValueChanged<int> onRemove;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return ScoreboardPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ScoreboardSectionTitle('Tichu calls'),
          for (final team in const [0, 1]) ...[
            if (team == 1) const Divider(color: Colors.white12, height: 20),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: scoreboardTeamColors[team],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    teamNames[team],
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
                if (calls.where((final c) => c.team == team).length < 2) ...[
                  _AddCallButton(
                    label: 'Tichu',
                    onTap: () => onAdd(team, TichuCallKind.tichu),
                  ),
                  const SizedBox(width: 6),
                  _AddCallButton(
                    label: 'Grand',
                    onTap: () => onAdd(team, TichuCallKind.grandTichu),
                  ),
                ],
              ],
            ),
            for (var i = 0; i < calls.length; i++)
              if (calls[i].team == team)
                _CallRow(
                  call: calls[i],
                  onSuccessChanged: (final s) => onSuccessChanged(i, s),
                  onRemove: () => onRemove(i),
                ),
            if (!calls.any((final c) => c.team == team))
              Padding(
                padding: const EdgeInsets.only(left: 18, top: 4),
                child: Text(
                  'No call',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white38,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AddCallButton extends StatelessWidget {
  const _AddCallButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) => ActionChip(
    avatar: const Icon(Icons.add, size: 16, color: Colors.white70),
    label: Text(label),
    labelStyle: const TextStyle(color: Colors.white),
    backgroundColor: Colors.white.withValues(alpha: 0.06),
    side: const BorderSide(color: Colors.white24),
    visualDensity: VisualDensity.compact,
    onPressed: onTap,
  );
}

class _CallRow extends StatelessWidget {
  const _CallRow({
    required this.call,
    required this.onSuccessChanged,
    required this.onRemove,
  });

  final TichuCall call;
  final ValueChanged<bool> onSuccessChanged;
  final VoidCallback onRemove;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 18, top: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  call.kind.label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  signedPoints(call.points),
                  style: theme.textTheme.bodySmall
                      ?.merge(scoreboardTabular)
                      .copyWith(
                        color: call.success
                            ? Colors.greenAccent
                            : Colors.redAccent,
                      ),
                ),
              ],
            ),
          ),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              selectedBackgroundColor: call.success
                  ? Colors.green.withValues(alpha: 0.45)
                  : Colors.red.withValues(alpha: 0.45),
            ),
            segments: const [
              ButtonSegment(
                value: true,
                icon: Icon(Icons.check, size: 18),
                label: Text('Made'),
              ),
              ButtonSegment(
                value: false,
                icon: Icon(Icons.close, size: 18),
                label: Text('Failed'),
              ),
            ],
            selected: {call.success},
            onSelectionChanged: (final s) => onSuccessChanged(s.first),
          ),
          IconButton(
            tooltip: 'Remove call',
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            color: Colors.white54,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _RoundSummaryBar extends StatelessWidget {
  const _RoundSummaryBar({
    required this.teamNames,
    required this.round,
    required this.errors,
    required this.onSave,
  });

  final List<String> teamNames;
  final ScoreboardRound round;
  final List<String> errors;
  final VoidCallback? onSave;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    Widget total(final int team) {
      final points = round.totalFor(team);
      return Expanded(
        child: Column(
          children: [
            Text(
              teamNames[team],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scoreboardTeamColors[team],
              ),
            ),
            Text(
              signedPoints(points),
              style: theme.textTheme.titleLarge
                  ?.merge(scoreboardTabular)
                  .copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: const Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      e,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    total(0),
                    total(1),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: onSave,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.secondary,
                        foregroundColor: Colors.black87,
                        minimumSize: const Size(120, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('Save'),
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
}
