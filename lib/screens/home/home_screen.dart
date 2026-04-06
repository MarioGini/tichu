import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/screens/shared/keyboard_shortcuts.dart';
import 'package:tichu/screens/shared/player_control.dart';
import 'package:tichu/services/local/local_table_service.dart';
import 'package:tichu/widgets/card_widget.dart';

enum _HomeKeyboardSection { matchLength, playerControl }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<int> _scoreOptions = [500, 1000, 1500, 2000];
  int _targetScore = 1000;
  PlayerControlMode _selfControlMode = PlayerControlMode.manual;
  final FocusNode _keyboardFocusNode = FocusNode();
  _HomeKeyboardSection _keyboardSection = _HomeKeyboardSection.matchLength;
  Future<void>? _cardPrecacheFuture;
  bool _didKickoffPrecache = false;
  bool _isPrecacheReady = false;
  bool _isStarting = false;

  bool get _canStart => _isPrecacheReady && !_isStarting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didKickoffPrecache) return;
    _didKickoffPrecache = true;
    final precacheFuture = CardWidget.precacheCardAssets(context);
    unawaited(
      precacheFuture.whenComplete(() {
        if (!mounted) return;
        setState(() {
          _isPrecacheReady = true;
        });
      }),
    );
    _cardPrecacheFuture = precacheFuture;
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _startSinglePlayer() async {
    if (!_canStart) return;
    setState(() {
      _isStarting = true;
    });
    try {
      await (_cardPrecacheFuture ?? CardWidget.precacheCardAssets(context));
      final tableService = LocalGameTableService();
      final displayName = _selfControlMode == PlayerControlMode.ai
          ? 'You (AI)'
          : 'You';
      final sessionHandle = await tableService.createLobby(
        CreateGameLobbyRequest(
          displayName: displayName,
          targetScore: _targetScore,
          preferredSeat: 0,
        ),
      );
      await tableService.claimSeat(
        sessionHandle.lobbyId,
        accessToken: sessionHandle.accessToken,
        seat: 0,
        type: _selfControlMode == PlayerControlMode.ai
            ? PlayerType.automated
            : PlayerType.human,
      );
      await tableService.claimSeat(
        sessionHandle.lobbyId,
        accessToken: sessionHandle.accessToken,
        seat: 1,
        type: PlayerType.automated,
        automatedDisplayName: 'Opponent 1',
      );
      await tableService.claimSeat(
        sessionHandle.lobbyId,
        accessToken: sessionHandle.accessToken,
        seat: 2,
        type: PlayerType.automated,
        automatedDisplayName: 'Opponent 2',
      );
      await tableService.claimSeat(
        sessionHandle.lobbyId,
        accessToken: sessionHandle.accessToken,
        seat: 3,
        type: PlayerType.automated,
        automatedDisplayName: 'Opponent 3',
      );
      await tableService.setReadyState(
        sessionHandle.lobbyId,
        accessToken: sessionHandle.accessToken,
        isReady: true,
      );
      final lobbyUpdates = tableService.watchLobby(
        sessionHandle.lobbyId,
        accessToken: sessionHandle.accessToken,
      );
      await tableService.startMatch(
        sessionHandle.lobbyId,
        accessToken: sessionHandle.accessToken,
      );
      final activeLobby = await lobbyUpdates.firstWhere(
        (final snapshot) => snapshot.matchId != null,
      );
      final activeHandle = sessionHandle.copyWith(
        seat: 0,
        matchId: activeLobby.matchId,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GameScreen(
            matchService: tableService,
            sessionHandle: activeHandle,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  void _onKeyboardLeft() {
    if (_keyboardSection == _HomeKeyboardSection.matchLength) {
      final currentIndex = _scoreOptions.indexOf(_targetScore);
      if (currentIndex > 0) {
        setState(() {
          _targetScore = _scoreOptions[currentIndex - 1];
        });
      }
      return;
    }

    if (_selfControlMode == PlayerControlMode.ai) {
      setState(() {
        _selfControlMode = PlayerControlMode.manual;
      });
    }
  }

  void _onKeyboardRight() {
    if (_keyboardSection == _HomeKeyboardSection.matchLength) {
      final currentIndex = _scoreOptions.indexOf(_targetScore);
      if (currentIndex < _scoreOptions.length - 1) {
        setState(() {
          _targetScore = _scoreOptions[currentIndex + 1];
        });
      }
      return;
    }

    if (_selfControlMode == PlayerControlMode.manual) {
      setState(() {
        _selfControlMode = PlayerControlMode.ai;
      });
    }
  }

  void _onKeyboardUp() {
    if (_keyboardSection != _HomeKeyboardSection.matchLength) {
      setState(() {
        _keyboardSection = _HomeKeyboardSection.matchLength;
      });
    }
  }

  void _onKeyboardDown() {
    if (_keyboardSection != _HomeKeyboardSection.playerControl) {
      setState(() {
        _keyboardSection = _HomeKeyboardSection.playerControl;
      });
    }
  }

  void _onKeyboardEnter() {
    if (!_canStart) return;
    unawaited(_startSinglePlayer());
  }

  @override
  Widget build(final BuildContext context) {
    final sliderValue = _scoreOptions.indexOf(_targetScore).toDouble();
    return Scaffold(
      body: Focus(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: (final node, final event) => handleDirectionalEnterKeyEvent(
          event,
          onEnter: _onKeyboardEnter,
          onLeft: _onKeyboardLeft,
          onRight: _onKeyboardRight,
          onUp: _onKeyboardUp,
          onDown: _onKeyboardDown,
        ),
        child: DecoratedBox(
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
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 32,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          child: const Icon(
                            Icons.style,
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
                        const SizedBox(height: 24),
                        _buildSection(
                          isActive:
                              _keyboardSection ==
                              _HomeKeyboardSection.matchLength,
                          child: _buildMatchLengthSection(sliderValue),
                        ),
                        const SizedBox(height: 24),
                        _buildSection(
                          isActive:
                              _keyboardSection ==
                              _HomeKeyboardSection.playerControl,
                          child: _buildPlayerControlSection(),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: !_canStart
                                ? null
                                : () => unawaited(_startSinglePlayer()),
                            icon: const Icon(Icons.play_arrow),
                            label: Text(
                              !_isPrecacheReady
                                  ? 'Warming up cards...'
                                  : _isStarting
                                  ? 'Preparing cards...'
                                  : 'Single Player Mode',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required final bool isActive,
    required final Widget child,
  }) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isActive
            ? Theme.of(context).colorScheme.primary
            : Colors.transparent,
      ),
    ),
    child: child,
  );

  Widget _buildMatchLengthSection(final double sliderValue) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Match length',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
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

  Widget _buildPlayerControlSection() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Your player control',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      const SizedBox(height: 8),
      SegmentedButton<PlayerControlMode>(
        segments: const [
          ButtonSegment<PlayerControlMode>(
            value: PlayerControlMode.manual,
            label: Text('Manual'),
            icon: Icon(Icons.person),
          ),
          ButtonSegment<PlayerControlMode>(
            value: PlayerControlMode.ai,
            label: Text('AI'),
            icon: Icon(Icons.smart_toy),
          ),
        ],
        selected: {_selfControlMode},
        showSelectedIcon: false,
        onSelectionChanged: (final selection) {
          setState(() {
            _selfControlMode = selection.first;
          });
        },
      ),
      const SizedBox(height: 8),
      Text(
        _selfControlMode == PlayerControlMode.manual
            ? 'You play manually; opponents are AI.'
            : 'AI controls your seat too so you can watch full AI play.',
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
    ],
  );
}
