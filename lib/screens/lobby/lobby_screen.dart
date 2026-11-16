import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
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
                                _buildHeader(context, lobby, localSeat),
                                const SizedBox(height: 10),
                                LayoutBuilder(
                                  builder: (final context, final constraints) {
                                    final columns = constraints.maxWidth >= 560
                                        ? 4
                                        : 2;
                                    const gap = 10.0;
                                    final tileW =
                                        (constraints.maxWidth -
                                            gap * (columns - 1)) /
                                        columns;
                                    return Wrap(
                                      spacing: gap,
                                      runSpacing: gap,
                                      children: [
                                        for (final seat in lobby.seats)
                                          SizedBox(
                                            width: tileW,
                                            child: _buildSeatCard(
                                              context,
                                              seat,
                                            ),
                                          ),
                                      ],
                                    );
                                  },
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
                        _buildActions(context, lobby, localSeat, hasOpenSeats),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildActions(
    final BuildContext context,
    final GameLobbySnapshot lobby,
    final GameLobbySeatSnapshot? localSeat,
    final bool hasOpenSeats,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isReady = localSeat?.isReady ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        border: const Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _isBusy ? null : () => unawaited(_leaveLobby()),
            icon: const Icon(Icons.exit_to_app),
            label: const Text('Leave'),
          ),
          if (lobby.isLocalPlayerHost &&
              widget.multiplayerBackend.supportsAutomatedSeats &&
              hasOpenSeats)
            OutlinedButton.icon(
              onPressed: _isBusy
                  ? null
                  : () => unawaited(_fillOpenSeatsWithBots()),
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('Fill with bots'),
            ),
          ElevatedButton.icon(
            onPressed: localSeat == null || _isBusy
                ? null
                : () => unawaited(_toggleReady()),
            icon: Icon(
              isReady ? Icons.pause_circle_outline : Icons.check_circle_outline,
            ),
            label: Text(isReady ? 'Not ready' : 'Ready'),
          ),
          if (lobby.isLocalPlayerHost)
            FilledButton.icon(
              onPressed: lobby.canStart && !_isBusy
                  ? () => unawaited(_startMatch())
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.secondary,
                foregroundColor: Colors.black87,
              ),
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('Start match'),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    final BuildContext context,
    final GameLobbySnapshot lobby,
    final GameLobbySeatSnapshot? localSeat,
  ) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 10,
    runSpacing: 6,
    children: [
      Text(
        'First to ${lobby.targetScore} • '
        '${lobby.visibility == GameLobbyVisibility.private ? "Private" : "Public"}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      if (lobby.visibility == GameLobbyVisibility.private)
        OutlinedButton.icon(
          onPressed: lobby.joinCode == null ? null : _copyJoinCode,
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: Text('Code: ${lobby.joinCode ?? ""}'),
        ),
      Chip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(
          lobby.isLocalPlayerHost ? Icons.star : Icons.person_outline,
          size: 16,
        ),
        label: Text(
          lobby.isLocalPlayerHost ? 'You are host' : 'Waiting for host',
        ),
      ),
      Text(
        localSeat == null
            ? 'Pick a seat to join the table.'
            : 'You: ${localSeat.seat.isEven ? "Team 1" : "Team 2"}, seat ${localSeat.seat + 1}',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
      ),
    ],
  );

  Widget _buildSeatCard(
    final BuildContext context,
    final GameLobbySeatSnapshot seat,
  ) {
    final isLocalSeat = seat.playerId == widget.sessionHandle.playerId;
    final isOpen = seat.state == GameLobbySeatState.open;
    final canClaim = isOpen && !_isBusy;
    final teamColor = seat.seat.isEven
        ? const Color(0xFF67D99A)
        : const Color(0xFFF2C94C);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isLocalSeat ? 0.32 : 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLocalSeat ? teamColor : Colors.white12,
          width: isLocalSeat ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: teamColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${seat.seat.isEven ? "Team 1" : "Team 2"} • Seat ${seat.seat + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: Colors.white70),
                ),
              ),
              if (isLocalSeat)
                Text(
                  'YOU',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: teamColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                isOpen
                    ? Icons.event_seat_outlined
                    : seat.type == PlayerType.automated
                    ? Icons.smart_toy_outlined
                    : Icons.person,
                size: 20,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _seatPrimaryLabel(seat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _seatSecondaryLabel(seat),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white60),
          ),
          if (isOpen) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: canClaim
                    ? () => unawaited(_claimSeat(seat.seat))
                    : null,
                child: const Text('Sit here'),
              ),
            ),
          ],
        ],
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
      return 'Free seat';
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
