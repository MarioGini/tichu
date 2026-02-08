import 'package:flutter/material.dart' hide Card;

import '../view_model/turn/tichu_data.dart';
import 'card_widget.dart';

class OpponentDisplay extends StatelessWidget {
  const OpponentDisplay({
    super.key,
    required this.name,
    required this.cardCount,
    required this.isActive,
    required this.tichuDeclared,
    required this.grandTichuDeclared,
    required this.finishPosition,
    required this.alignment,
    required this.icon,
    this.pendingCards = const [],
    this.pendingPass = false,
  });

  final String name;
  final int cardCount;
  final bool isActive;
  final bool tichuDeclared;
  final bool grandTichuDeclared;
  final int? finishPosition;
  final Axis alignment;
  final IconData icon;
  final List<Card> pendingCards;
  final bool pendingPass;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = alignment == Axis.horizontal;
    final colorScheme = Theme.of(context).colorScheme;
    final hasPending = pendingPass || pendingCards.isNotEmpty;
    final showIconInline = !isHorizontal;
    final badgeColor = grandTichuDeclared
        ? Colors.deepOrange
        : tichuDeclared
        ? Colors.orange
        : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isActive ? 0.35 : 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? Colors.amber : Colors.white24,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Flex(
        direction: isHorizontal ? Axis.horizontal : Axis.vertical,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!showIconInline)
            Icon(
              icon,
              color: colorScheme.onSurface.withValues(alpha: 0.9),
              size: isHorizontal ? 22 : 28,
            ),
          if (!showIconInline)
            SizedBox(width: isHorizontal ? 8 : 0, height: isHorizontal ? 0 : 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showIconInline)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          color: colorScheme.onSurface.withValues(alpha: 0.9),
                          size: 22,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          name,
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(color: Colors.white),
                        ),
                      ],
                    )
                  else
                    Text(
                      name,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: Colors.white),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '$cardCount cards',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? colorScheme.secondary.withValues(alpha: 0.18)
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isActive
                            ? colorScheme.secondary
                            : Colors.white24,
                      ),
                    ),
                    child: Text(
                      isActive ? 'Their turn' : 'Waiting',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isActive
                            ? colorScheme.secondary
                            : Colors.white70,
                      ),
                    ),
                  ),
                  if (finishPosition != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Out #$finishPosition',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.greenAccent,
                        ),
                      ),
                    ),
                  if (hasPending)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: pendingPass
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amberAccent),
                              ),
                              child: Text(
                                'PASS',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Colors.amberAccent,
                                      letterSpacing: 1.6,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            )
                          : Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final card in pendingCards)
                                  CardWidget(
                                    card: card,
                                    isSelected: false,
                                    compact: true,
                                    scale: 0.7,
                                  ),
                              ],
                            ),
                    ),
                ],
              ),
            ),
          ),
          if (badgeColor != null)
            Padding(
              padding: EdgeInsets.only(
                left: isHorizontal ? 8 : 0,
                top: isHorizontal ? 0 : 8,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  grandTichuDeclared ? 'Grand Tichu' : 'Tichu',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
