part of 'schupf_panel.dart';

/// Vertical padding consumed by the container in [buildSchupfPanelContainer].
const double _containerPadding = 24; // 12 top + 12 bottom

double _contentWidth(final SchupfLayout layout, final int cardCount) {
  final overlapCount = cardCount > 1 ? cardCount - 1 : 0;
  final handNaturalWidth =
      layout.rowCardWidth +
      overlapCount * (layout.rowCardWidth + layout.rowSpacing);
  return layout.targetRowWidth > handNaturalWidth
      ? layout.targetRowWidth
      : handNaturalWidth;
}

double _panelWidth(
  final BoxConstraints constraints,
  final SchupfLayout layout,
  final int cardCount,
) {
  final contentWidth = _contentWidth(layout, cardCount);
  return constraints.maxWidth.isFinite
      ? (contentWidth + 24).clamp(0.0, constraints.maxWidth)
      : contentWidth + 24;
}

Widget _title(final BuildContext context, final String text) => Text(
  text,
  style: Theme.of(context).textTheme.titleMedium?.copyWith(
    color: Colors.white,
    fontWeight: FontWeight.w600,
  ),
);

/// Short screens: title and button next to the three slots.
Widget _compactTopRow(
  final BuildContext context, {
  required final String title,
  required final List<Widget> targets,
  required final Widget button,
  required final double maxWidth,
  final String? hint,
}) => SizedBox(
  width: maxWidth,
  child: FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        targets[0],
        const SizedBox(width: 10),
        targets[1],
        const SizedBox(width: 10),
        targets[2],
        const SizedBox(width: 20),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(context, title),
            if (hint != null)
              Text(
                hint,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: Colors.white60),
              ),
            const SizedBox(height: 8),
            button,
          ],
        ),
      ],
    ),
  ),
);

Widget _targetRow(final List<Widget> targets, {final double? maxWidth}) {
  final row = Row(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      targets[0],
      const SizedBox(width: 12),
      targets[1],
      const SizedBox(width: 12),
      targets[2],
    ],
  );

  if (maxWidth == null) return row;

  return SizedBox(
    width: maxWidth,
    child: FittedBox(fit: BoxFit.scaleDown, child: row),
  );
}
