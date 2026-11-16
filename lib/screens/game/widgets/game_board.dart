import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:tichu/widgets/card_widget.dart';
import 'package:tichu/widgets/game_gradient_background.dart';
import 'package:tichu/widgets/played_card_size_scope.dart';

part 'game_board_landscape.dart';

/// Whether a screen of [size] gets the phone-landscape table: wider than
/// tall. Opponents are then drawn as wide pills instead of square tiles.
bool isLandscapeTable(final Size size) => size.width > size.height;

/// Game table layout for portrait and landscape screens.
///
/// Portrait (phones held upright): top bar, the table (partner on top,
/// opponents at the side edges, trick in the middle), the action buttons and
/// the hand anchored to the bottom edge.
///
/// Landscape (phones turned sideways, tablets, desktop): height is the scarce
/// resource, so the partner shares the top bar with the score, the side
/// opponents sit in narrow columns at the edges, the trick and the action
/// buttons share the centre column and the hand spans the full width at the
/// bottom.
///
/// With [expandHand] (schupf phase) the hand area gets the space the trick
/// would use, since there is no trick yet.
class GameBoard extends StatelessWidget {
  const GameBoard({
    super.key,
    required this.topOpponent,
    required this.leftOpponent,
    required this.rightOpponent,
    required this.trickArea,
    required this.handArea,
    required this.actionBar,
    this.topBarLeading = const SizedBox.shrink(),
    this.topBarCenter = const SizedBox.shrink(),
    this.topBarTrailing = const SizedBox.shrink(),
    this.expandHand = false,
    this.reserveTopPendingSlot = true,
    this.reserveSidePendingSlots = true,
    this.topPendingSlot = const SizedBox.shrink(),
    this.leftPendingSlot = const SizedBox.shrink(),
    this.rightPendingSlot = const SizedBox.shrink(),
  });

  final Widget topOpponent;
  final Widget leftOpponent;
  final Widget rightOpponent;
  final Widget trickArea;
  final Widget handArea;
  final Widget actionBar;

  /// Top bar: back button, score, options button.
  final Widget topBarLeading;
  final Widget topBarCenter;
  final Widget topBarTrailing;

  /// Give the hand area the room of the (empty) trick, e.g. while schupfing.
  final bool expandHand;
  final bool reserveTopPendingSlot;
  final bool reserveSidePendingSlots;

  /// Partner's staged play (cards shown before they move to the trick).
  final Widget topPendingSlot;

  /// Left opponent's staged play.
  final Widget leftPendingSlot;

  /// Right opponent's staged play.
  final Widget rightPendingSlot;

  @override
  Widget build(final BuildContext context) => GameGradientBackground(
    child: LayoutBuilder(
      builder: (final context, final constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (isLandscapeTable(Size(w, h))) {
          return _landscape(w, h);
        }
        return _portrait(w, h);
      },
    ),
  );

  // ── Portrait ─────────────────────────────────────────────────────────

  Widget _portrait(final double w, final double h) {
    const topBarH = 48.0;
    final hPad = w < 600 ? 4.0 : 12.0;
    final handMaxH = expandHand ? h * 0.62 : math.min(h * 0.36, 300).toDouble();

    return Column(
      children: [
        SizedBox(
          height: topBarH,
          child: Row(
            children: [
              topBarLeading,
              Expanded(child: Center(child: topBarCenter)),
              topBarTrailing,
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (final context, final table) =>
                _portraitTable(table.maxWidth, table.maxHeight),
          ),
        ),
        // While schupfing the panel holds its own button; the remaining
        // actions (Tichu) go below it.
        if (!expandHand) actionBar,
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 2, hPad, expandHand ? 0 : 6),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: handMaxH),
            child: handArea,
          ),
        ),
        if (expandHand) actionBar,
      ],
    );
  }

  Widget _portraitTable(final double w, final double h) {
    const pad = 4.0;
    const gap = 4.0;
    final op = math.min(w * 0.24, math.min(h * 0.26, 108)).toDouble();
    // Trick: as large as the space between the side opponents allows.
    final trickW = math.min<double>(w - 2 * (op + pad + gap), 320);
    final idealTrickH = math
        .min(h - 2 * (op + gap) - 8, CardWidget.normalHeight + 56)
        .clamp(60.0, 400.0);
    final pendingH = math.min(math.max(0, idealTrickH - 44) * 0.6, op);
    // The partner's staged play sits between the partner and the trick;
    // the trick starts below it (and shrinks on short screens) so the two
    // never overlap.
    final topReserve =
        op + gap + (reserveTopPendingSlot ? pendingH + gap : 0).toDouble();
    final trickH = math
        .max(60, math.min(idealTrickH, h - topReserve - 4))
        .toDouble();
    final laneH = math.max(0, trickH - 44).toDouble();
    final playedCardScale =
        (math.max(0, laneH - 8) / (CardWidget.normalHeight + 8)).clamp(
          0.25,
          1.0,
        );
    final pendingW = CardWidget.normalWidth * playedCardScale * 1.6;
    final trickTop = math.max(topReserve, (h - trickH) / 2 + op * 0.2);

    return PlayedCardSizeScope(
      cardScale: playedCardScale,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: (w - op) / 2,
            child: SizedBox.square(dimension: op, child: topOpponent),
          ),
          Positioned(
            left: pad,
            top: (h - op) / 2,
            child: SizedBox.square(dimension: op, child: leftOpponent),
          ),
          Positioned(
            right: pad,
            top: (h - op) / 2,
            child: SizedBox.square(dimension: op, child: rightOpponent),
          ),
          Positioned(
            left: (w - trickW) / 2,
            top: math.min(trickTop, math.max(0, h - trickH)),
            width: trickW,
            height: trickH,
            child: trickArea,
          ),
          // Staged plays go on top of everything else.
          if (reserveTopPendingSlot)
            Positioned(
              top: op + gap,
              left: (w - pendingW) / 2,
              width: pendingW,
              height: pendingH,
              child: topPendingSlot,
            ),
          if (reserveSidePendingSlots) ...[
            Positioned(
              left: pad,
              top: (h + op) / 2 + gap,
              width: op,
              height: pendingH,
              child: leftPendingSlot,
            ),
            Positioned(
              right: pad,
              top: (h + op) / 2 + gap,
              width: op,
              height: pendingH,
              child: rightPendingSlot,
            ),
          ],
        ],
      ),
    );
  }
}
