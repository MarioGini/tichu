import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' hide Card;
import 'package:tichu/agents/app_bots.dart';
import 'package:tichu/agents/smart_ai_agent.dart';
import 'package:tichu/game/driver_ui_projector.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_match.dart';
import 'package:tichu/game/game_play_controller.dart';
import 'package:tichu/game/game_session.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/wish_logic.dart';
import 'package:tichu/screens/game/round_summary_screen.dart';
import 'package:tichu/screens/game/widgets/game_board.dart';
import 'package:tichu/screens/game/widgets/grand_tichu_banner.dart';
import 'package:tichu/screens/game/widgets/options_dialog.dart';
import 'package:tichu/screens/game/widgets/player_hand_area.dart';
import 'package:tichu/screens/game/widgets/schupf_layout.dart';
import 'package:tichu/screens/game/widgets/score_bar.dart';
import 'package:tichu/screens/game/widgets/tichu_celebration_overlay.dart';
import 'package:tichu/screens/game/widgets/trick_event_overlay.dart';
import 'package:tichu/screens/game/widgets/wish_dialog.dart';
import 'package:tichu/screens/shared/keyboard_shortcuts.dart';
import 'package:tichu/screens/shared/player_control.dart';
import 'package:tichu/services/sound_effects.dart';
import 'package:tichu/widgets/action_bar.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/opponent_display.dart';
import 'package:tichu/widgets/pending_play_slot.dart';
import 'package:tichu/widgets/trick_display.dart';

part 'parts/game_screen_actions.dart';
part 'parts/game_screen_dialogs.dart';
part 'parts/game_screen_logic.dart';
part 'parts/game_screen_round_end.dart';
part 'parts/game_screen_seats.dart';
part 'parts/game_screen_input.dart';
part 'parts/game_screen_state.dart';
part 'parts/game_screen_suggestion.dart';
part 'parts/game_screen_sync.dart';
part 'parts/game_screen_view.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required GameMatchService matchService,
    required GameSessionHandle sessionHandle,
    double initialOpponentDelaySeconds = 1.0,
  }) : _matchService = matchService,
       _sessionHandle = sessionHandle,
       _initialOpponentDelaySeconds = initialOpponentDelaySeconds;
  final GameMatchService _matchService;
  final GameSessionHandle _sessionHandle;
  final double _initialOpponentDelaySeconds;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends _GameScreenStateBase
    with
        _GameScreenSync,
        _GameScreenSuggestion,
        _GameScreenActions,
        _GameScreenHelpers,
        _GameScreenDialogs,
        _GameScreenRoundEnd,
        _GameScreenInput,
        _GameScreenSeats,
        _GameScreenView {
  @override
  void initState() {
    super.initState();
    _matchService = widget._matchService;
    _sessionHandle = widget._sessionHandle;
    _humanId = _sessionHandle.playerId;
    _selfSeat = _sessionHandle.seat;
    _bombController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _bombSlide = Tween<Offset>(begin: const Offset(0, -1.6), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _bombController, curve: Curves.easeInCubic),
        );
    _bombScale = Tween<double>(begin: 0.85, end: 1).animate(
      CurvedAnimation(parent: _bombController, curve: Curves.easeOutBack),
    );
    _bombController.addStatusListener((final status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 280), () {
          if (!mounted) return;
          setState(() {
            _showBombOverlay = false;
          });
        });
      }
    });
    // Move hints come from the same bot the app plays against.
    _suggestionAgent = AppBots.current.build(_humanId) as SmartAiAgent;
    _opponentDelaySeconds = widget._initialOpponentDelaySeconds;
    unawaited(_initializeMatch());
  }

  @override
  Widget build(final BuildContext context) => _buildTable(context);
}
