import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/screens/home/widgets/home_dialogs.dart';
import 'package:tichu/screens/home/widgets/home_start_panel.dart';
import 'package:tichu/screens/home/widgets/open_games_panel.dart';
import 'package:tichu/screens/lobby/lobby_screen.dart';
import 'package:tichu/screens/observe/observe_screen.dart';
import 'package:tichu/screens/scoreboard/scoreboard_screen.dart';
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
  // Keeps the start panel (and the name field's focus) alive when the
  // layout switches, e.g. when the on-screen keyboard shrinks the screen
  // below the short-screen breakpoint.
  final GlobalKey _startPanelKey = GlobalKey();
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

    final result = await showDialog<CreateGameResult>(
      context: context,
      builder: (final context) => CreateGameDialog(displayName: _displayName),
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
      builder: (final context) => const JoinPrivateDialog(),
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
              final start = HomeStartPanel(
                key: _startPanelKey,
                compact: wide,
                nameController: _displayNameController,
                onNameChanged: (_) => setState(() {}),
                showSolo: _multiplayerBackend.supportsAutomatedSeats,
                canAct: _canAct,
                isBusy: _isBusy,
                onPlaySolo: () => unawaited(_playSolo()),
                onObserve: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ObserveScreen(),
                  ),
                ),
                onScoreboard: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ScoreboardScreen(),
                  ),
                ),
                onCreate: () => unawaited(_showCreateGameDialog()),
                onJoinWithCode: () => unawaited(_showJoinPrivateDialog()),
              );
              final games = OpenGamesPanel(
                publicGames: publicGames,
                canJoin: _canAct,
                onRefresh: () => unawaited(_refreshGames()),
                onJoin: (final entry) => unawaited(_joinGame(entry)),
              );
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
}
