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

/// Enter one real-life round: Tichu calls, match (double victory) and
/// counted card points.
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

  void _update(ScoreboardRound round) => setState(() => _round = round);

  void _setDoubleVictory(int? team) {
    // The match team went out first, so a call by the other team
    // has failed.
    final calls = _round.calls
        .map(
          (c) =>
              team != null && c.team != team ? c.copyWith(success: false) : c,
        )
        .toList();
    _update(_round.copyWith(doubleVictoryTeam: () => team, calls: calls));
  }

  void _setCardPoints(int teamA) => _update(
    _round.copyWith(
      cardPointsTeamA: teamA.clamp(
        ScoreboardRound.minCardPoints,
        ScoreboardRound.maxCardPoints,
      ),
    ),
  );

  void _addCall(int team, TichuCallKind kind) {
    final dv = _round.doubleVictoryTeam;
    final canSucceed =
        !_round.calls.any((c) => c.success) && (dv == null || dv == team);
    _update(
      _round.copyWith(
        calls: [
          ..._round.calls,
          TichuCall(team: team, kind: kind, success: canSucceed),
        ],
      ),
    );
  }

  void _setCallSuccess(int index, bool success) {
    // Only one player goes out first: making one call fails the others.
    final calls = List.generate(_round.calls.length, (i) {
      final call = _round.calls[i];
      if (i == index) return call.copyWith(success: success);
      return success ? call.copyWith(success: false) : call;
    });
    _update(_round.copyWith(calls: calls));
  }

  void _removeCall(int index) =>
      _update(_round.copyWith(calls: [..._round.calls]..removeAt(index)));

  void _save() {
    if (!_round.isValid) return;
    Navigator.of(context).pop(RoundEntrySaved(_round));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
  Widget build(BuildContext context) {
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
                        _CallsSection(
                          teamNames: widget.teamNames,
                          calls: _round.calls,
                          onAdd: _addCall,
                          onSuccessChanged: _setCallSuccess,
                          onRemove: _removeCall,
                        ),
                        const SizedBox(height: 12),
                        _MatchSection(
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

class _MatchSection extends StatelessWidget {
  const _MatchSection({
    required this.teamNames,
    required this.value,
    required this.onChanged,
  });

  final List<String> teamNames;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => ScoreboardPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScoreboardSectionTitle('Match (1-2 finish)'),
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
          onSelectionChanged: (s) => onChanged(s.first == -1 ? null : s.first),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doubleVictory = round.doubleVictoryTeam != null;
    final a = round.cardPointsFor(0);
    Widget side(int team, int points) => Expanded(
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
            doubleVictory ? 'Card points (match)' : 'Card points',
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
                'Cards are not counted: the match scores 200.',
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
              activeColor: scoreboardTeamColors[0],
              inactiveColor: scoreboardTeamColors[1].withValues(alpha: 0.6),
              onChanged: (v) => onChanged(v.round()),
            ),
          ],
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget column(int team) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            teamNames[team],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: scoreboardTeamColors[team],
            ),
          ),
          for (var i = 0; i < calls.length; i++)
            if (calls[i].team == team)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _CallPill(
                  call: calls[i],
                  onSuccessChanged: (s) => onSuccessChanged(i, s),
                  onRemove: () => onRemove(i),
                ),
              ),
          if (calls.where((c) => c.team == team).length < 2)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _AddCallButton(
                      label: 'Tichu',
                      onTap: () => onAdd(team, TichuCallKind.tichu),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _AddCallButton(
                      label: 'Grand',
                      onTap: () => onAdd(team, TichuCallKind.grandTichu),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    return ScoreboardPanel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ScoreboardSectionTitle('Tichu calls'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [column(0), const SizedBox(width: 12), column(1)],
          ),
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
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white24),
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    icon: const Icon(Icons.add, size: 16),
    label: Text(label),
  );
}

/// A call as a compact pill: name, made / failed toggles, remove.
class _CallPill extends StatelessWidget {
  const _CallPill({
    required this.call,
    required this.onSuccessChanged,
    required this.onRemove,
  });

  final TichuCall call;
  final ValueChanged<bool> onSuccessChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final color = call.success ? Colors.greenAccent : Colors.redAccent;
    Widget toggle({
      required bool value,
      required IconData icon,
      required String tooltip,
    }) {
      final selected = call.success == value;
      final c = value ? Colors.greenAccent : Colors.redAccent;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onSuccessChanged(value),
          child: Semantics(
            button: true,
            selected: selected,
            label: tooltip,
            child: Container(
              width: 28,
              height: 26,
              decoration: BoxDecoration(
                color: selected ? c.withValues(alpha: 0.3) : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: selected ? c : Colors.white38),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              call.kind == TichuCallKind.tichu ? 'Tichu' : 'Grand',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          toggle(value: true, icon: Icons.check, tooltip: 'Made'),
          toggle(value: false, icon: Icons.close, tooltip: 'Failed'),
          IconButton(
            tooltip: 'Remove call',
            icon: const Icon(Icons.delete_outline, size: 16),
            color: Colors.white38,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget total(int team) {
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
