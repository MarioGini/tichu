import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Card;
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/record/game_record.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/observe/observe_controller.dart';
import 'package:tichu/services/records/default_game_record_store.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/game_gradient_background.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';

part 'observe_widgets.dart';

/// Watch four bots play, one move at a time. Every hand is face up; the
/// move a bot has chosen is shown (its cards lifted) until Continue.
class ObserveScreen extends StatefulWidget {
  const ObserveScreen({super.key, this.controller});

  /// Injected in tests; otherwise the screen creates (and disposes) one.
  final ObserveController? controller;

  @override
  State<ObserveScreen> createState() => _ObserveScreenState();
}

class _ObserveScreenState extends State<ObserveScreen> {
  late final ObserveController _controller =
      widget.controller ??
      ObserveController(store: createDefaultGameRecordStore());
  final ScrollController _logScroll = ScrollController();
  final FocusNode _focus = FocusNode(debugLabel: 'observe');
  int _shownEvents = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    if (_controller.gameId == null) unawaited(_controller.start());
    _shownEvents = -1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChanged());
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (widget.controller == null) _controller.dispose();
    _logScroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    final count = _controller.record?.events.length ?? 0;
    if (count != _shownEvents) {
      _shownEvents = count;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScroll.hasClients) {
          _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
        }
      });
    }
  }

  KeyEventResult _onKey(final FocusNode node, final KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.arrowRight) {
      unawaited(_controller.continueGame());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _copy(final String text, final String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$what copied')));
  }

  Future<void> _showRecordInfo() async {
    final id = _controller.gameId;
    if (id == null) return;
    await showDialog<void>(
      context: context,
      builder: (final context) => AlertDialog(
        title: const Text('Game record'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Game ID'),
            SelectableText(id, style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 12),
            const Text('Saved to'),
            SelectableText(
              _controller.recordLocation ?? 'not saved',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Refer to moves by their # number. Tap a log entry to see '
              'the hand the bot had at that moment.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => unawaited(_copy(id, 'Game ID')),
            child: const Text('Copy ID'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(final BuildContext context) {
    final snapshot = _controller.snapshot;
    final record = _controller.record;
    final score = snapshot?.scoreState;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Watch AI'),
              if (score != null)
                Text(
                  'Round ${score.roundNumber} · '
                  'Team A ${score.teamOneTotal} : ${score.teamTwoTotal} Team B',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
            ],
          ),
          actions: [
            if (record != null) ...[
              IconButton(
                tooltip: 'Copy game ID',
                icon: const Icon(Icons.tag),
                onPressed: () => unawaited(_copy(record.id, 'Game ID')),
              ),
              IconButton(
                tooltip: 'Copy full record (JSON)',
                icon: const Icon(Icons.copy_all),
                onPressed: () => unawaited(
                  _copy(
                    const JsonEncoder.withIndent('  ').convert(record.toJson()),
                    'Record',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Record info',
                icon: const Icon(Icons.info_outline),
                onPressed: () => unawaited(_showRecordInfo()),
              ),
            ],
          ],
        ),
        body: GameGradientBackground(
          child: SafeArea(
            child: snapshot == null || record == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (final context, final constraints) {
                      final table = _ObserveTable(
                        snapshot: snapshot,
                        record: record,
                      );
                      final log = _EventLog(
                        record: record,
                        scrollController: _logScroll,
                      );
                      final wide = constraints.maxWidth >= 900;
                      return Column(
                        children: [
                          Expanded(
                            child: wide
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(child: table),
                                      SizedBox(width: 380, child: log),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      Expanded(flex: 3, child: table),
                                      Expanded(flex: 2, child: log),
                                    ],
                                  ),
                          ),
                          _ControlBar(controller: _controller),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
