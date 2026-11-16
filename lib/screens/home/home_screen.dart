import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/screens/lobby/lobby_screen.dart';
import 'package:tichu/services/multiplayer/multiplayer_backend.dart';
import 'package:tichu/services/multiplayer/solo_match.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, final MultiplayerBackend? multiplayerBackend})
    : _multiplayerBackend = multiplayerBackend;

  final MultiplayerBackend? _multiplayerBackend;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MultiplayerBackend _multiplayerBackend =
      widget._multiplayerBackend ?? LocalMultiplayerBackend();
  final TextEditingController _displayNameController = TextEditingController(
    text: 'Player',
  );
  bool _isBusy = false;
  List<GameLobbyListEntry> _games = const <GameLobbyListEntry>[];
  Timer? _refreshTimer;

  String get _displayName => _displayNameController.text.trim();

  bool get _canAct => !_isBusy && _displayName.isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshGames());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshGames(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _refreshGames() async {
    try {
      final games = await _multiplayerBackend.sessionService.listGames();
      if (mounted) {
        setState(() {
          _games = games;
        });
      }
    } on Object catch (_) {}
  }

  Future<void> _showCreateGameDialog() async {
    if (!_canAct) return;

    final result = await showDialog<_CreateGameResult>(
      context: context,
      builder: (final context) => _CreateGameDialog(displayName: _displayName),
    );
    if (result == null || !mounted) return;

    await _runBusyAction(() async {
      final handle = await _multiplayerBackend.sessionService.createLobby(
        CreateGameLobbyRequest(
          displayName: _displayName,
          gameName: result.gameName,
          targetScore: result.targetScore,
          preferredTeam: result.preferredTeam,
          visibility: result.visibility,
        ),
      );
      await _openLobby(handle);
    });
  }

  Future<void> _showJoinPrivateDialog() async {
    if (!_canAct) return;

    final code = await showDialog<String>(
      context: context,
      builder: (final context) => const _JoinPrivateDialog(),
    );
    if (code == null || code.isEmpty || !mounted) return;

    await _runBusyAction(() async {
      final handle = await _multiplayerBackend.sessionService.joinLobby(
        JoinGameLobbyRequest(joinCode: code, displayName: _displayName),
      );
      await _openLobby(handle);
    });
  }

  Future<void> _joinGame(final GameLobbyListEntry entry) async {
    if (!_canAct) return;
    await _runBusyAction(() async {
      final handle = await _multiplayerBackend.sessionService.joinLobby(
        JoinGameLobbyRequest(
          joinCode: entry.lobbyId,
          displayName: _displayName,
        ),
      );
      await _openLobby(handle);
    });
  }

  Future<void> _playSolo() async {
    if (!_canAct) return;
    await _runBusyAction(() async {
      final handle = await startSoloMatch(
        _multiplayerBackend,
        displayName: _displayName,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GameScreen(
            matchService: _multiplayerBackend.matchService,
            sessionHandle: handle,
          ),
        ),
      );
    });
  }

  Future<void> _openLobby(final GameSessionHandle sessionHandle) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LobbyScreen(
          multiplayerBackend: _multiplayerBackend,
          sessionHandle: sessionHandle,
        ),
      ),
    );
    unawaited(_refreshGames());
  }

  Future<void> _runBusyAction(final Future<void> Function() action) async {
    setState(() {
      _isBusy = true;
    });
    try {
      await action();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  @override
  Widget build(final BuildContext context) {
    final publicGames = _games
        .where((final g) => g.visibility == GameLobbyVisibility.public)
        .toList();

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.3,
            colors: [Color(0xFF1C7A50), Color(0xFF0F5D3D), Color(0xFF07301F)],
            stops: [0, 0.55, 1],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (final context, final constraints) {
              final wide =
                  constraints.maxWidth > constraints.maxHeight &&
                  constraints.maxWidth >= 640;
              final start = _buildStartPanel(context, compact: wide);
              final games = _buildGamesPanel(context, publicGames);
              if (wide) {
                // Landscape: start actions left, open games right.
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: start,
                              ),
                            ),
                          ),
                          Expanded(child: games),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (constraints.maxHeight < 560) {
                // Short screens: scroll, with a fixed-height games list.
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          start,
                          const SizedBox(height: 16),
                          SizedBox(height: 240, child: games),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        start,
                        const SizedBox(height: 16),
                        Expanded(child: games),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStartPanel(
    final BuildContext context, {
    required final bool compact,
  }) {
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
          controller: _displayNameController,
          onChanged: (_) => setState(() {}),
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
        if (_multiplayerBackend.supportsAutomatedSeats)
          FilledButton.icon(
            onPressed: _canAct ? () => unawaited(_playSolo()) : null,
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
            icon: _isBusy
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
                onPressed: _canAct
                    ? () => unawaited(_showCreateGameDialog())
                    : null,
                style: _secondaryButtonStyle,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Create game'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _canAct
                    ? () => unawaited(_showJoinPrivateDialog())
                    : null,
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

  Widget _buildGamesPanel(
    final BuildContext context,
    final List<GameLobbyListEntry> publicGames,
  ) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 0),
            child: Row(
              children: [
                const Icon(Icons.public, size: 18, color: Colors.white70),
                const SizedBox(width: 8),
                Text('Open games', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  onPressed: () => unawaited(_refreshGames()),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: publicGames.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No open games right now.\nCreate one or play vs AI.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    itemCount: publicGames.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Colors.white12),
                    itemBuilder: (final context, final index) =>
                        _buildGameTile(context, publicGames[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameTile(
    final BuildContext context,
    final GameLobbyListEntry entry,
  ) {
    final title = entry.gameName.isNotEmpty
        ? entry.gameName
        : "${entry.hostDisplayName}'s Game";
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: CircleAvatar(
        child: Text('${entry.occupiedSeats}/${entry.totalSeats}'),
      ),
      title: Text(title),
      subtitle: Text(
        'Host: ${entry.hostDisplayName} • First to ${entry.targetScore}',
      ),
      trailing: FilledButton(
        onPressed: _canAct ? () => unawaited(_joinGame(entry)) : null,
        child: const Text('Join'),
      ),
    );
  }
}

class _CreateGameResult {
  final String gameName;
  final int targetScore;
  final int preferredTeam;
  final GameLobbyVisibility visibility;

  const _CreateGameResult({
    required this.gameName,
    required this.targetScore,
    required this.preferredTeam,
    required this.visibility,
  });
}

class _CreateGameDialog extends StatefulWidget {
  const _CreateGameDialog({required this.displayName});

  final String displayName;

  @override
  State<_CreateGameDialog> createState() => _CreateGameDialogState();
}

class _CreateGameDialogState extends State<_CreateGameDialog> {
  static const List<int> _scoreOptions = [500, 1000, 1500, 2000];

  late final TextEditingController _gameNameController = TextEditingController(
    text: "${widget.displayName}'s Game",
  );
  int _targetScore = 1000;
  int _preferredTeam = 0;
  GameLobbyVisibility _visibility = GameLobbyVisibility.public;

  @override
  void dispose() {
    _gameNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final sliderValue = _scoreOptions.indexOf(_targetScore).toDouble();

    return AlertDialog(
      title: const Text('Create Game'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _gameNameController,
                decoration: const InputDecoration(
                  labelText: 'Game name',
                  hintText: 'Name your game',
                ),
              ),
              const SizedBox(height: 20),
              Text('Visibility', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<GameLobbyVisibility>(
                segments: const [
                  ButtonSegment<GameLobbyVisibility>(
                    value: GameLobbyVisibility.public,
                    label: Text('Public'),
                    icon: Icon(Icons.public),
                  ),
                  ButtonSegment<GameLobbyVisibility>(
                    value: GameLobbyVisibility.private,
                    label: Text('Private'),
                    icon: Icon(Icons.lock_outlined),
                  ),
                ],
                selected: <GameLobbyVisibility>{_visibility},
                showSelectedIcon: false,
                onSelectionChanged: (final selection) {
                  setState(() {
                    _visibility = selection.first;
                  });
                },
              ),
              if (_visibility == GameLobbyVisibility.private)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Private games need the join code to enter.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Team preference',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(value: 0, label: Text('Team 1')),
                  ButtonSegment<int>(value: 1, label: Text('Team 2')),
                ],
                selected: <int>{_preferredTeam},
                showSelectedIcon: false,
                onSelectionChanged: (final selection) {
                  setState(() {
                    _preferredTeam = selection.first;
                  });
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Match length',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text('First team to $_targetScore points'),
              Slider(
                value: sliderValue,
                max: (_scoreOptions.length - 1).toDouble(),
                divisions: _scoreOptions.length - 1,
                label: '$_targetScore',
                onChanged: (final value) {
                  setState(() {
                    _targetScore = _scoreOptions[value.round().clamp(0, 3)];
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _CreateGameResult(
                gameName: _gameNameController.text.trim(),
                targetScore: _targetScore,
                preferredTeam: _preferredTeam,
                visibility: _visibility,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _JoinPrivateDialog extends StatefulWidget {
  const _JoinPrivateDialog();

  @override
  State<_JoinPrivateDialog> createState() => _JoinPrivateDialogState();
}

class _JoinPrivateDialogState extends State<_JoinPrivateDialog> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) => AlertDialog(
    title: const Text('Join Private Game'),
    content: TextField(
      controller: _codeController,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(
        labelText: 'Join code',
        hintText: 'Enter the 5-digit game code',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final code = _codeController.text.trim().toUpperCase();
          Navigator.of(context).pop(code);
        },
        child: const Text('Join'),
      ),
    ],
  );
}
