import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tichu/scoreboard/scoreboard_model.dart';
import 'package:tichu/scoreboard/scoreboard_store.dart';
import 'package:tichu/screens/scoreboard/round_entry_screen.dart';
import 'package:tichu/screens/scoreboard/scoreboard_colors.dart';
import 'package:tichu/screens/scoreboard/scoreboard_setup.dart';
import 'package:tichu/widgets/game_gradient_background.dart';

/// Score sheet for Tichu played with real cards: enter each round, the app
/// keeps the totals. The match in progress survives app restarts.
class ScoreboardScreen extends StatefulWidget {
  const ScoreboardScreen({super.key, this.store});

  /// Defaults to device-local storage.
  final ScoreboardStore? store;

  @override
  State<ScoreboardScreen> createState() => _ScoreboardScreenState();
}

class _ScoreboardScreenState extends State<ScoreboardScreen> {
  late final ScoreboardStore _store =
      widget.store ?? SharedPreferencesScoreboardStore();
  bool _loading = true;
  ScoreboardGame? _game;

  /// Shows the setup form instead of the sheet (new match / edit teams).
  bool _setup = false;

  /// The setup form edits the current match rather than starting one.
  bool _editing = false;

  ScaffoldMessengerState? _messenger;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    // A pending "Undo" must not outlive this screen.
    _messenger?.hideCurrentSnackBar();
    super.dispose();
  }

  Future<void> _load() async {
    ScoreboardGame? game;
    try {
      game = await _store.loadCurrent();
    } on Object catch (_) {}
    if (!mounted) return;
    setState(() {
      _game = game;
      _setup = game == null;
      _loading = false;
    });
  }

  void _setGame(final ScoreboardGame game) {
    setState(() => _game = game);
    unawaited(_save(game));
  }

  Future<void> _save(final ScoreboardGame game) async {
    try {
      await _store.saveCurrent(game);
    } on Object catch (error) {
      _messenger?.showSnackBar(
        SnackBar(content: Text('Could not save the score sheet: $error')),
      );
    }
  }

  void _onSetup(final ScoreboardSetupResult result) {
    final current = _game;
    final game = current != null && _editing
        ? current.copyWith(
            teamNames: result.teamNames,
            targetScore: result.targetScore,
          )
        : ScoreboardGame.start(
            teamNames: result.teamNames,
            targetScore: result.targetScore,
          );
    _setup = false;
    _editing = false;
    _setGame(game);
  }

  Future<void> _newMatch() async {
    final game = _game;
    if (game != null && game.rounds.isNotEmpty && !game.isFinished) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (final context) => AlertDialog(
          title: const Text('Start a new match?'),
          content: const Text('The current score sheet will be discarded.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('New match'),
            ),
          ],
        ),
      );
      if (!(confirmed ?? false) || !mounted) return;
    }
    // Keep the team names for the next match at the same table. Saved now
    // so the discarded rounds do not come back when the screen reopens.
    if (game != null) _setGame(game.copyWith(rounds: const []));
    setState(() {
      _setup = true;
      _editing = false;
    });
  }

  Future<void> _openRound([final int? index]) async {
    final game = _game;
    if (game == null) return;
    // Round indices may shift: drop a pending "Undo" of a deletion.
    _messenger?.hideCurrentSnackBar();
    final result = await Navigator.of(context).push<RoundEntryResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RoundEntryScreen(
          teamNames: game.teamNames,
          roundNumber: (index ?? game.rounds.length) + 1,
          initial: index == null ? null : game.rounds[index],
        ),
      ),
    );
    if (!mounted || result == null) return;
    final current = _game!;
    switch (result) {
      case RoundEntrySaved(:final round):
        _setGame(
          index == null
              ? current.addRound(round)
              : current.replaceRound(index, round),
        );
      case RoundEntryDeleted():
        if (index != null) _removeRound(index);
    }
  }

  void _removeRound(final int index) {
    final game = _game!;
    final removed = game.rounds[index];
    _setGame(game.removeRound(index));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Round ${index + 1} deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              final current = _game;
              if (!mounted || current == null) return;
              // Re-insert only the deleted round, keeping later changes.
              final at = index.clamp(0, current.rounds.length);
              _setGame(
                current.copyWith(
                  rounds: [...current.rounds]..insert(at, removed),
                ),
              );
            },
          ),
        ),
      );
  }

  @override
  Widget build(final BuildContext context) {
    final game = _game;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Scoreboard'),
        actions: [
          if (game != null && !_setup) ...[
            if (game.rounds.isNotEmpty)
              IconButton(
                tooltip: 'Undo last round',
                icon: const Icon(Icons.undo),
                onPressed: () => _removeRound(game.rounds.length - 1),
              ),
            PopupMenuButton<String>(
              onSelected: (final v) {
                if (v == 'edit') {
                  setState(() {
                    _setup = true;
                    _editing = true;
                  });
                }
                if (v == 'new') unawaited(_newMatch());
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Teams & target'),
                  ),
                ),
                PopupMenuItem(
                  value: 'new',
                  child: ListTile(
                    leading: Icon(Icons.restart_alt),
                    title: Text('New match'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: GameGradientBackground(
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _setup || game == null
              ? _buildSetup(game)
              : _ScoreSheet(
                  game: game,
                  onAddRound: () => unawaited(_openRound()),
                  onEditRound: (final i) => unawaited(_openRound(i)),
                  onNewMatch: () => unawaited(_newMatch()),
                ),
        ),
      ),
    );
  }

  Widget _buildSetup(final ScoreboardGame? game) {
    final editing = game != null && _editing;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                editing ? 'Teams & target' : 'New match',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                editing
                    ? 'Rounds already entered are kept.'
                    : 'Keep score of a game played with real cards.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white60),
              ),
              const SizedBox(height: 16),
              ScoreboardSetupForm(
                initialTeamNames: game?.teamNames ?? const ['Team A', 'Team B'],
                initialTargetScore: game?.targetScore ?? 1000,
                submitLabel: editing ? 'Save' : 'Start match',
                onSubmit: _onSetup,
              ),
              if (editing) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _setup = false;
                    _editing = false;
                  }),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreSheet extends StatelessWidget {
  const _ScoreSheet({
    required this.game,
    required this.onAddRound,
    required this.onEditRound,
    required this.onNewMatch,
  });

  final ScoreboardGame game;
  final VoidCallback onAddRound;
  final ValueChanged<int> onEditRound;
  final VoidCallback onNewMatch;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    final totals = game.runningTotals;
    final winner = game.winner;
    final header = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: _TotalsHeader(game: game),
      ),
      if (winner != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _WinnerBanner(game: game, winner: winner),
        ),
    ];
    final roundsTitle = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: ScoreboardSectionTitle(
        game.rounds.isEmpty ? 'Rounds' : 'Rounds (${game.rounds.length})',
        trailing: game.rounds.isEmpty
            ? null
            : Text(
                'Tap to edit',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white38,
                ),
              ),
      ),
    );
    final roundsList = Expanded(
      child: game.rounds.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.style_outlined,
                      size: 48,
                      color: Colors.white24,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Deal, play, count your cards,\n'
                      'then add the round here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              itemCount: game.rounds.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, final i) {
                // Newest round first.
                final index = game.rounds.length - 1 - i;
                return _RoundRow(
                  number: index + 1,
                  round: game.rounds[index],
                  totals: totals[index],
                  onTap: () => onEditRound(index),
                );
              },
            ),
    );
    final addButton = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: FilledButton.icon(
        onPressed: winner == null ? onAddRound : onNewMatch,
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.secondary,
          foregroundColor: Colors.black87,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        icon: Icon(winner == null ? Icons.add : Icons.restart_alt),
        label: Text(
          winner == null ? 'Add round ${game.rounds.length + 1}' : 'New match',
        ),
      ),
    );
    return LayoutBuilder(
      builder: (final context, final constraints) {
        if (constraints.maxWidth > constraints.maxHeight &&
            constraints.maxWidth >= 640) {
          // Landscape: totals and the button left, rounds right.
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: header,
                            ),
                          ),
                        ),
                        addButton,
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [roundsTitle, roundsList],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...header, roundsTitle, roundsList, addButton],
            ),
          ),
        );
      },
    );
  }
}

class _TotalsHeader extends StatelessWidget {
  const _TotalsHeader({required this.game});

  final ScoreboardGame game;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    final last = game.rounds.isEmpty ? null : game.rounds.last;
    final a = game.totalFor(0);
    final b = game.totalFor(1);
    Widget team(final int t, final int total, final bool leading) {
      final color = scoreboardTeamColors[t];
      return Expanded(
        child: ScoreboardPanel(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      game.teamNames[t],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (leading)
                    const Icon(
                      Icons.emoji_events,
                      size: 16,
                      color: Color(0xFFF2C94C),
                    ),
                ],
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$total',
                  style: theme.textTheme.displayMedium
                      ?.merge(scoreboardTabular)
                      .copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                ),
              ),
              Text(
                last == null
                    ? 'to ${game.targetScore}'
                    : '${signedPoints(last.totalFor(t))} last round',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (total / game.targetScore).clamp(0, 1).toDouble(),
                  minHeight: 6,
                  color: color,
                  backgroundColor: Colors.white10,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            team(0, a, a > b),
            const SizedBox(width: 10),
            team(1, b, b > a),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          game.rounds.isEmpty
              ? 'Playing to ${game.targetScore}'
              : 'Playing to ${game.targetScore} · '
                    '${(a - b).abs() == 0 ? 'level' : '${(a - b).abs()} apart'}',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(color: Colors.white54),
        ),
      ],
    );
  }
}

class _WinnerBanner extends StatelessWidget {
  const _WinnerBanner({required this.game, required this.winner});

  final ScoreboardGame game;
  final int winner;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF2C94C), Color(0xFFE0A526)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: Colors.black87, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${game.teamNames[winner]} win!',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.black87,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${game.totalFor(winner)} : ${game.totalFor(1 - winner)} '
                  'after ${game.rounds.length} rounds',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundRow extends StatelessWidget {
  const _RoundRow({
    required this.number,
    required this.round,
    required this.totals,
    required this.onTap,
  });

  final int number;
  final ScoreboardRound round;
  final List<int> totals;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final theme = Theme.of(context);
    Widget side(final int team) {
      final points = round.totalFor(team);
      final badges = <Widget>[
        if (round.doubleVictoryTeam == team)
          const _Badge(label: 'Match', color: Color(0xFFF2C94C)),
        for (final c in round.calls)
          if (c.team == team)
            _Badge(
              label: c.kind == TichuCallKind.tichu ? 'T' : 'GT',
              icon: c.success ? Icons.check : Icons.close,
              color: c.success ? Colors.greenAccent : Colors.redAccent,
            ),
      ];
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  signedPoints(points),
                  style: theme.textTheme.titleMedium
                      ?.merge(scoreboardTabular)
                      .copyWith(
                        color: points < 0
                            ? Colors.redAccent.shade100
                            : Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${totals[team]}',
                  style: theme.textTheme.bodySmall
                      ?.merge(scoreboardTabular)
                      .copyWith(color: Colors.white38),
                ),
              ],
            ),
            if (badges.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Wrap(spacing: 4, runSpacing: 4, children: badges),
              ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.black.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  '$number',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white38,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              side(0),
              side(1),
              const Icon(Icons.chevron_right, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(final BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (icon != null) ...[
          const SizedBox(width: 2),
          Icon(icon, size: 12, color: color),
        ],
      ],
    ),
  );
}
