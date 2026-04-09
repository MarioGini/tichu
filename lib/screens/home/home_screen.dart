import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tichu/game/game_session.dart';
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
  static const List<int> _scoreOptions = [500, 1000, 1500, 2000];

  late final MultiplayerBackend _multiplayerBackend =
      widget._multiplayerBackend ?? LocalMultiplayerBackend();
  final TextEditingController _displayNameController = TextEditingController(
    text: 'Player',
  );
  final TextEditingController _joinCodeController = TextEditingController();
  int _targetScore = 1000;
  int _preferredSeat = 0;
  bool _isBusy = false;

  String get _displayName => _displayNameController.text.trim();

  String get _joinCode => _joinCodeController.text.trim().toUpperCase();

  bool get _canCreate => !_isBusy && _displayName.isNotEmpty;

  bool get _canJoin =>
      !_isBusy && _displayName.isNotEmpty && _joinCode.isNotEmpty;

  @override
  void dispose() {
    _displayNameController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _createLobby() async {
    if (!_canCreate) return;
    await _runBusyAction(() async {
      final sessionHandle = await _multiplayerBackend.sessionService
          .createLobby(
            CreateGameLobbyRequest(
              displayName: _displayName,
              targetScore: _targetScore,
              preferredSeat: _preferredSeat,
            ),
          );
      await _openLobby(sessionHandle);
    });
  }

  Future<void> _joinLobby() async {
    if (!_canJoin) return;
    await _runBusyAction(() async {
      final sessionHandle = await _multiplayerBackend.sessionService.joinLobby(
        JoinGameLobbyRequest(
          joinCode: _joinCode,
          displayName: _displayName,
          preferredSeat: _preferredSeat,
        ),
      );
      await _openLobby(sessionHandle);
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
    final sliderValue = _scoreOptions.indexOf(_targetScore).toDouble();

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
              constraints: const BoxConstraints(maxWidth: 680),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        child: const Icon(
                          Icons.groups_rounded,
                          size: 56,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'TICHU',
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Create a lobby or join one with a code.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      _buildBackendBanner(context),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _displayNameController,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          hintText: 'Enter your player name',
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSeatPreferenceSection(context),
                      const SizedBox(height: 24),
                      _buildMatchLengthSection(context, sliderValue),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _joinCodeController,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Join code',
                          hintText: 'Enter a lobby code to join',
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _canCreate
                                  ? () => unawaited(_createLobby())
                                  : null,
                              icon: const Icon(Icons.add_circle_outline),
                              label: Text(
                                _isBusy ? 'Working...' : 'Create Lobby',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _canJoin
                                  ? () => unawaited(_joinLobby())
                                  : null,
                              icon: const Icon(Icons.login),
                              label: const Text('Join Lobby'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _multiplayerBackend.supportsAutomatedSeats
                            ? 'Local tables can fill remaining seats with bots from the lobby screen.'
                            : 'Supabase lobbies expect other clients to join with the same code.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackendBanner(final BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.4),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            Icons.hub_outlined,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Backend', style: Theme.of(context).textTheme.labelLarge),
                Text(
                  _multiplayerBackend.displayName,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildSeatPreferenceSection(final BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Seat preference', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment<int>(value: 0, label: Text('1')),
          ButtonSegment<int>(value: 1, label: Text('2')),
          ButtonSegment<int>(value: 2, label: Text('3')),
          ButtonSegment<int>(value: 3, label: Text('4')),
        ],
        selected: <int>{_preferredSeat},
        showSelectedIcon: false,
        onSelectionChanged: (final selection) {
          setState(() {
            _preferredSeat = selection.first;
          });
        },
      ),
    ],
  );

  Widget _buildMatchLengthSection(
    final BuildContext context,
    final double sliderValue,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Match length', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        'First team to $_targetScore points',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
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
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: _scoreOptions
            .map(
              (final score) => Text(
                score.toString(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            )
            .toList(),
      ),
    ],
  );
}
