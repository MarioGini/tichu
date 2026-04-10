import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/screens/lobby/lobby_screen.dart';
import 'package:tichu/services/multiplayer/multiplayer_backend.dart';

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
    } catch (_) {}
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
      final service = _multiplayerBackend.sessionService;
      final handle = await service.createLobby(
        CreateGameLobbyRequest(
          displayName: _displayName,
          gameName: '$_displayName vs Bots',
          visibility: GameLobbyVisibility.private,
        ),
      );
      await service.setReadyState(
        handle.lobbyId,
        accessToken: handle.accessToken,
        isReady: true,
      );
      for (var seat = 0; seat < 4; seat++) {
        final lobby = await service
            .watchLobby(handle.lobbyId, accessToken: handle.accessToken)
            .first;
        final seatState = lobby.seats[seat];
        if (seatState.state == GameLobbySeatState.open) {
          await service.claimSeat(
            handle.lobbyId,
            accessToken: handle.accessToken,
            seat: seat,
            type: PlayerType.automated,
            automatedDisplayName: 'Bot ${seat + 1}',
          );
        }
      }
      await service.startMatch(handle.lobbyId, accessToken: handle.accessToken);
      final activeLobby = await service
          .watchLobby(handle.lobbyId, accessToken: handle.accessToken)
          .firstWhere((final s) => s.matchId != null);
      final localSeat = activeLobby.seats.firstWhere(
        (final s) => s.playerId == handle.playerId,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GameScreen(
            matchService: _multiplayerBackend.matchService,
            sessionHandle: handle.copyWith(
              seat: localSeat.seat,
              matchId: activeLobby.matchId,
            ),
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
    } catch (error) {
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
          gradient: LinearGradient(
            colors: [Color(0xFF0B4A30), Color(0xFF0F5D3D), Color(0xFF134E4A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'TICHU',
                            style: Theme.of(context).textTheme.headlineMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _displayNameController,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Display name',
                              hintText: 'Enter your player name',
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              if (_multiplayerBackend.supportsAutomatedSeats)
                                FilledButton.icon(
                                  onPressed: _canAct
                                      ? () => unawaited(_playSolo())
                                      : null,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Play Solo'),
                                ),
                              ElevatedButton.icon(
                                onPressed: _canAct
                                    ? () => unawaited(_showCreateGameDialog())
                                    : null,
                                icon: const Icon(Icons.add_circle_outline),
                                label: const Text('Create Game'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _canAct
                                    ? () => unawaited(_showJoinPrivateDialog())
                                    : null,
                                icon: const Icon(Icons.lock_outlined),
                                label: const Text('Join Private Game'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Text(
                                'Open Games',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () => unawaited(_refreshGames()),
                                icon: const Icon(Icons.refresh),
                                tooltip: 'Refresh',
                              ),
                            ],
                          ),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                    Expanded(
                      child: publicGames.isEmpty
                          ? Center(
                              child: Text(
                                'No open games. Create one!',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 8,
                              ),
                              itemCount: publicGames.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (final context, final index) =>
                                  _buildGameTile(context, publicGames[index]),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameTile(
    final BuildContext context,
    final GameLobbyListEntry entry,
  ) {
    final title = entry.gameName.isNotEmpty
        ? entry.gameName
        : '${entry.hostDisplayName}\'s Game';
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
    text: '${widget.displayName}\'s Game',
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
