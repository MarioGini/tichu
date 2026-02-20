import 'package:flutter/material.dart';

BoxDecoration buildPlayerStateFrameDecoration({
  required bool isActive,
  required bool isFinished,
  required double borderRadius,
  double idleAlpha = 0.2,
}) {
  final Color borderColor;
  final double borderWidth;
  if (isFinished) {
    borderColor = Colors.greenAccent;
    borderWidth = 2.5;
  } else if (isActive) {
    borderColor = Colors.amber;
    borderWidth = 2;
  } else {
    borderColor = Colors.white24;
    borderWidth = 1;
  }

  return BoxDecoration(
    color: Colors.black.withValues(alpha: isActive ? 0.35 : idleAlpha),
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: borderColor, width: borderWidth),
  );
}

Widget buildPlayerOutLabel(BuildContext context, int finishPosition) {
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      'Out #$finishPosition',
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: Colors.greenAccent),
    ),
  );
}
