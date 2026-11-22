import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Card;
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/record/game_record.dart';
import 'package:tichu/game/scoring/score_tracker.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/screens/game/widgets/game_board.dart';
import 'package:tichu/screens/game/widgets/player_hand_area.dart';
import 'package:tichu/screens/game/widgets/score_bar.dart';
import 'package:tichu/screens/game/widgets/top_bar_button.dart';
import 'package:tichu/screens/observe/observe_controller.dart';
import 'package:tichu/screens/shared/table_seats.dart';
import 'package:tichu/services/records/default_game_record_store.dart';
import 'package:tichu/services/supabase/supabase_app_client.dart';
import 'package:tichu/services/supabase/supabase_game_record_store.dart';
import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/game_gradient_background.dart';
import 'package:tichu/widgets/opponent_display.dart';
import 'package:tichu/widgets/overlapping_card_row.dart';
import 'package:tichu/widgets/pending_play_slot.dart';
import 'package:tichu/widgets/trick_display.dart';

part 'observe_table.dart';
part 'observe_widgets.dart';

/// Watch four bots play, one move at a time, on the normal game table.
///
/// The followed bot ([ObserveController.followedSeat]) sits at the bottom
/// with its hand face up, the other three sit around the table exactly as
/// partner and opponents do in a normal game. Tap a seat to follow that bot
/// instead (the table rotates); "All hands" in the menu shows every hand.
/// A bot's chosen move is staged (its cards lifted or shown next to its
/// seat) until Step.
class ObserveScreen extends StatefulWidget {
  const ObserveScreen({super.key, this.controller});

  /// Injected in tests; otherwise the screen creates (and disposes) one.
  final ObserveController? controller;

  @override
  State<ObserveScreen> createState() => _ObserveScreenState();
}

enum _MenuAction { allHands, copyId, copyRecord, recordInfo }

class _ObserveScreenState extends State<ObserveScreen> {
  late final ObserveController _controller =
      widget.controller ??
      ObserveController(
        // Watched games go to Supabase so they can be discussed later by id;
        // builds without a Supabase project fall back to local files.
        store: supabaseConfigured
            ? SupabaseGameRecordStore()
            : createDefaultGameRecordStore(),
      );
  final FocusNode _focus = FocusNode(debugLabel: 'observe');

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    if (_controller.gameId == null) unawaited(_controller.start());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(CardWidget.precacheCardAssets(context));
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (widget.controller == null) _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
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
    if (key == LogicalKeyboardKey.keyP) {
      _controller.setAutoPlay(!_controller.autoPlay);
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
            const SizedBox(height: 4),
            Text(_uploadStatus().$2),
            const SizedBox(height: 12),
            const Text('Refer to moves by the # number shown next to Step.'),
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

  Future<void> _showAllHands() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF0B3B2A),
    showDragHandle: true,
    builder: (final context) => _AllHandsSheet(controller: _controller),
  );

  void _onMenu(final _MenuAction action) {
    final record = _controller.record;
    switch (action) {
      case _MenuAction.allHands:
        unawaited(_showAllHands());
      case _MenuAction.copyId:
        if (record != null) unawaited(_copy(record.id, 'Game ID'));
      case _MenuAction.copyRecord:
        if (record != null) {
          unawaited(
            _copy(
              const JsonEncoder.withIndent('  ').convert(record.toJson()),
              'Record',
            ),
          );
        }
      case _MenuAction.recordInfo:
        unawaited(_showRecordInfo());
    }
  }

  /// Icon and text describing where the record is being saved.
  (IconData, String) _uploadStatus() {
    final store = _controller.store;
    if (store is! SupabaseGameRecordStore) {
      return (
        Icons.save_outlined,
        'Saved locally (this build has no Supabase project configured)',
      );
    }
    final error = store.lastError;
    if (error != null) return (Icons.cloud_off, 'Upload failed: $error');
    if (store.lastSavedAt == null) {
      return (Icons.cloud_upload_outlined, 'Uploading to Supabase…');
    }
    return (Icons.cloud_done_outlined, 'Saved to Supabase');
  }

  Widget _topBarTrailing() {
    final (icon, status) = _uploadStatus();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TopBarButton(
          key: const Key('observe-upload-status'),
          tooltip: status,
          icon: icon,
          onPressed: _controller.gameId == null
              ? null
              : () => unawaited(_showRecordInfo()),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: PopupMenuButton<_MenuAction>(
            key: const Key('observe-menu'),
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.black.withValues(alpha: 0.22),
              fixedSize: const Size.square(40),
              minimumSize: const Size.square(40),
              padding: EdgeInsets.zero,
            ),
            onSelected: _onMenu,
            itemBuilder: (final context) => const [
              PopupMenuItem(
                value: _MenuAction.allHands,
                child: ListTile(
                  leading: Icon(Icons.style),
                  title: Text('All hands'),
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.copyId,
                child: ListTile(
                  leading: Icon(Icons.tag),
                  title: Text('Copy game ID'),
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.copyRecord,
                child: ListTile(
                  leading: Icon(Icons.copy_all),
                  title: Text('Copy full record (JSON)'),
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.recordInfo,
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Record info'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(final BuildContext context) {
    final snapshot = _controller.snapshot;
    final record = _controller.record;
    final leading = TopBarButton(
      tooltip: 'Leave table',
      icon: Icons.arrow_back_rounded,
      onPressed: () => Navigator.of(context).maybePop(),
    );
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: SafeArea(
          child: snapshot == null || record == null
              ? GameGradientBackground(
                  child: Stack(
                    children: [
                      Positioned(top: 4, left: 0, child: leading),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                )
              : _ObserveTable(
                  controller: _controller,
                  snapshot: snapshot,
                  record: record,
                  topBarLeading: leading,
                  topBarTrailing: _topBarTrailing(),
                ),
        ),
      ),
    );
  }
}
