import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/screens/game/game_screen.dart';
import 'package:tichu/screens/lobby/lobby_seats.dart';
import 'package:tichu/screens/lobby/lobby_widgets.dart';
import 'package:tichu/services/multiplayer/multiplayer_backend.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({
    super.key,
    required this.multiplayerBackend,
    required this.sessionHandle,
  });

  final MultiplayerBackend multiplayerBackend;
  final GameSessionHandle sessionHandle;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  StreamSubscription<GameLobbySnapshot>? _lobbySubscription;
  GameLobbySnapshot? _lobby;
  bool _isBusy = false;
  bool _isOpeningMatch = false;

  GameSessionService get _sessionService =>
      widget.multiplayerBackend.sessionService;

  @override
  void initState() {
    super.initState();
    _lobbySubscription = _sessionService
        .watchLobby(
          widget.sessionHandle.lobbyId,
          accessToken: widget.sessionHandle.accessToken,
        )
        .listen(_handleLobbySnapshot, onError: _handleLobbyError);
  }

  @override
  void dispose() {
    unawaited(_lobbySubscription?.cancel());
    super.dispose();
  }

  void _handleLobbySnapshot(final GameLobbySnapshot snapshot) {
    if (!mounted) return;
    setState(() {
      _lobby = snapshot;
    });
    if (snapshot.matchId != null && !_isOpeningMatch) {
      _isOpeningMatch = true;
      unawaited(_openMatch(snapshot));
    }
  }

  void _handleLobbyError(final Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }

  Future<void> _openMatch(final GameLobbySnapshot lobby) async {
    final matchId = lobby.matchId;
    if (matchId == null || !mounted) return;

    await _lobbySubscription?.cancel();
    final activeHandle = widget.sessionHandle.copyWith(
      seat: _localSeatSnapshot(lobby)?.seat,
      matchId: matchId,
    );
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          matchService: widget.multiplayerBackend.matchService,
          sessionHandle: activeHandle,
        ),
      ),
    );
  }

  Future<void> _copyJoinCode() async {
    final joinCode = _lobby?.joinCode;
    if (joinCode == null) return;
    await Clipboard.setData(ClipboardData(text: joinCode));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Join code copied.')));
  }

  Future<void> _claimSeat(final int seat) async {
    await _runLobbyAction(() async {
      await _sessionService.claimSeat(
        widget.sessionHandle.lobbyId,
        accessToken: widget.sessionHandle.accessToken,
        seat: seat,
      );
    });
  }

  Future<void> _toggleReady() async {
    final lobby = _lobby;
    final localSeat = lobby == null ? null : _localSeatSnapshot(lobby);
    if (localSeat == null) return;
    await _runLobbyAction(() async {
      await _sessionService.setReadyState(
        widget.sessionHandle.lobbyId,
        accessToken: widget.sessionHandle.accessToken,
        isReady: !localSeat.isReady,
      );
    });
  }

  Future<void> _fillOpenSeatsWithBots() async {
    final lobby = _lobby;
    if (lobby == null) return;
    final openSeats = <GameLobbySeatSnapshot>[
      for (final seat in lobby.seats)
        if (seat.state == GameLobbySeatState.open) seat,
    ];
    if (openSeats.isEmpty) return;

    await _runLobbyAction(() async {
      for (final seat in openSeats) {
        await _sessionService.claimSeat(
          widget.sessionHandle.lobbyId,
          accessToken: widget.sessionHandle.accessToken,
          seat: seat.seat,
          type: PlayerType.automated,
          automatedDisplayName: 'Bot ${seat.seat + 1}',
        );
      }
    });
  }

  Future<void> _startMatch() async {
    await _runLobbyAction(() async {
      await _sessionService.startMatch(
        widget.sessionHandle.lobbyId,
        accessToken: widget.sessionHandle.accessToken,
      );
    });
  }

  Future<void> _leaveLobby() async {
    await _runLobbyAction(() async {
      await _sessionService.leaveLobby(
        widget.sessionHandle.lobbyId,
        accessToken: widget.sessionHandle.accessToken,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _runLobbyAction(final Future<void> Function() action) async {
    if (_isBusy) return;
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

  GameLobbySeatSnapshot? _localSeatSnapshot(final GameLobbySnapshot lobby) {
    for (final seat in lobby.seats) {
      if (seat.playerId == widget.sessionHandle.playerId) {
        return seat;
      }
    }
    return null;
  }

  @override
  Widget build(final BuildContext context) {
    final lobby = _lobby;
    final localSeat = lobby == null ? null : _localSeatSnapshot(lobby);
    final hasOpenSeats =
        lobby != null &&
        lobby.seats.any((final seat) => seat.state == GameLobbySeatState.open);
    final size = MediaQuery.sizeOf(context);
    final shortScreen = size.height < 500;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: shortScreen ? 44 : null,
        backgroundColor: const Color(0xFF0B4A30),
        title: Text(
          lobby?.gameName.isNotEmpty == true ? lobby!.gameName : 'Game Lobby',
        ),
      ),
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
          top: false,
          child: lobby == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                LobbyHeader(
                                  lobby: lobby,
                                  localSeat: localSeat,
                                  onCopyJoinCode: _copyJoinCode,
                                ),
                                const SizedBox(height: 10),
                                LobbySeatGrid(
                                  seats: lobby.seats,
                                  localPlayerId: widget.sessionHandle.playerId,
                                  onClaim: _isBusy
                                      ? null
                                      : (final seat) =>
                                            unawaited(_claimSeat(seat)),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget
                                          .multiplayerBackend
                                          .supportsAutomatedSeats
                                      ? 'Invite people with the code or fill the empty seats with bots.'
                                      : 'Open another client on the same backend and join with this code.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.white60),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        LobbyActionBar(
                          lobby: lobby,
                          localSeat: localSeat,
                          hasOpenSeats: hasOpenSeats,
                          supportsBots:
                              widget.multiplayerBackend.supportsAutomatedSeats,
                          isBusy: _isBusy,
                          onLeave: () => unawaited(_leaveLobby()),
                          onFillWithBots: () =>
                              unawaited(_fillOpenSeatsWithBots()),
                          onToggleReady: () => unawaited(_toggleReady()),
                          onStart: () => unawaited(_startMatch()),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
