import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/screens/game/game_screen.dart';
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
    _lobbySubscription?.cancel();
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
        type: PlayerType.human,
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          lobby?.gameName.isNotEmpty == true ? lobby!.gameName : 'Game Lobby',
        ),
      ),
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
              constraints: const BoxConstraints(maxWidth: 980),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: lobby == null
                    ? const Center(child: CircularProgressIndicator())
                    : Card(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeader(context, lobby),
                              const SizedBox(height: 20),
                              Text(
                                localSeat == null
                                    ? 'Choose a team to join the table.'
                                    : 'You are on ${localSeat.seat.isEven ? "Team 1" : "Team 2"} (Seat ${localSeat.seat + 1}).',
                                style: Theme.of(context).textTheme.bodyLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  for (final seat in lobby.seats)
                                    _buildSeatCard(context, seat),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                alignment: WrapAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: localSeat == null || _isBusy
                                        ? null
                                        : () => unawaited(_toggleReady()),
                                    icon: Icon(
                                      localSeat?.isReady ?? false
                                          ? Icons.pause_circle_outline
                                          : Icons.check_circle_outline,
                                    ),
                                    label: Text(
                                      localSeat?.isReady ?? false
                                          ? 'Mark Not Ready'
                                          : 'Mark Ready',
                                    ),
                                  ),
                                  if (lobby.isLocalPlayerHost &&
                                      widget
                                          .multiplayerBackend
                                          .supportsAutomatedSeats &&
                                      hasOpenSeats)
                                    OutlinedButton.icon(
                                      onPressed: _isBusy
                                          ? null
                                          : () => unawaited(
                                              _fillOpenSeatsWithBots(),
                                            ),
                                      icon: const Icon(
                                        Icons.smart_toy_outlined,
                                      ),
                                      label: const Text(
                                        'Fill Empty Seats With Bots',
                                      ),
                                    ),
                                  if (lobby.isLocalPlayerHost)
                                    ElevatedButton.icon(
                                      onPressed: lobby.canStart && !_isBusy
                                          ? () => unawaited(_startMatch())
                                          : null,
                                      icon: const Icon(
                                        Icons.rocket_launch_outlined,
                                      ),
                                      label: const Text('Start Match'),
                                    ),
                                  OutlinedButton.icon(
                                    onPressed: _isBusy
                                        ? null
                                        : () => unawaited(_leaveLobby()),
                                    icon: const Icon(Icons.exit_to_app),
                                    label: const Text('Leave Game'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                widget.multiplayerBackend.supportsAutomatedSeats
                                    ? 'Invite other people with the code or fill the remaining seats with bots.'
                                    : 'Open another client on the same backend and join with this code.',
                                style: Theme.of(context).textTheme.bodyMedium,
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
      ),
    );
  }

  Widget _buildHeader(
    final BuildContext context,
    final GameLobbySnapshot lobby,
  ) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.35),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lobby.gameName.isNotEmpty) ...[
            Text(
              lobby.gameName,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
          ],
          Text(
            'First team to ${lobby.targetScore} • ${lobby.visibility == GameLobbyVisibility.private ? "Private" : "Public"}',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              if (lobby.visibility == GameLobbyVisibility.private)
                OutlinedButton.icon(
                  onPressed: lobby.joinCode == null ? null : _copyJoinCode,
                  icon: const Icon(Icons.copy_outlined),
                  label: Text('Code: ${lobby.joinCode ?? ""}'),
                ),
              Chip(
                avatar: Icon(
                  lobby.isLocalPlayerHost ? Icons.star : Icons.person_outline,
                  size: 18,
                ),
                label: Text(
                  lobby.isLocalPlayerHost ? 'You are host' : 'Waiting for host',
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildSeatCard(
    final BuildContext context,
    final GameLobbySeatSnapshot seat,
  ) {
    final isLocalSeat = seat.playerId == widget.sessionHandle.playerId;
    final isOpen = seat.state == GameLobbySeatState.open;
    final canClaim = isOpen && !_isBusy;

    return SizedBox(
      width: 280,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${seat.seat.isEven ? "Team 1" : "Team 2"} • Seat ${seat.seat + 1}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (isLocalSeat)
                    Chip(
                      label: const Text('You'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _seatPrimaryLabel(seat),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 6),
              Text(
                _seatSecondaryLabel(seat),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: canClaim
                      ? () => unawaited(_claimSeat(seat.seat))
                      : null,
                  child: Text(isOpen ? 'Claim Seat' : 'Seat Occupied'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _seatPrimaryLabel(final GameLobbySeatSnapshot seat) =>
      switch (seat.state) {
        GameLobbySeatState.open => 'Open seat',
        GameLobbySeatState.locked => 'Locked seat',
        GameLobbySeatState.occupied => seat.displayName ?? 'Seated player',
      };

  String _seatSecondaryLabel(final GameLobbySeatSnapshot seat) {
    if (seat.state == GameLobbySeatState.open) {
      return 'Tap to take this seat.';
    }
    if (seat.state == GameLobbySeatState.locked) {
      return 'Unavailable for this lobby.';
    }
    final readyLabel = seat.isReady ? 'ready' : 'not ready';
    final typeLabel = seat.type == PlayerType.automated ? 'bot' : 'human';
    final connectionLabel = seat.isConnected ? 'connected' : 'offline';
    return '$typeLabel • $readyLabel • $connectionLabel';
  }
}
