import 'package:material_ui/material_ui.dart';

/// Team colours on the scoreboard: team A green, team B orange.
const List<Color> scoreboardTeamColors = [Color(0xFF67D99A), Color(0xFFFFB74D)];

const TextStyle scoreboardTabular = TextStyle(
  fontFeatures: [FontFeature.tabularFigures()],
);

/// "+165", "−65", "0".
String signedPoints(int points) => points > 0
    ? '+$points'
    : points < 0
    ? '−${-points}'
    : '0';

/// Section container used on the scoreboard screens.
class ScoreboardPanel extends StatelessWidget {
  const ScoreboardPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white12),
    ),
    child: child,
  );
}

class ScoreboardSectionTitle extends StatelessWidget {
  const ScoreboardSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white60,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
