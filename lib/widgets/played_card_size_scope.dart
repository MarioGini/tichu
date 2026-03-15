import 'package:flutter/widgets.dart';

class PlayedCardSizeScope extends InheritedWidget {
  const PlayedCardSizeScope({
    super.key,
    required this.cardScale,
    required super.child,
  });

  final double cardScale;

  static double? maybeOf(final BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PlayedCardSizeScope>()
      ?.cardScale;

  @override
  bool updateShouldNotify(final PlayedCardSizeScope oldWidget) =>
      oldWidget.cardScale != cardScale;
}
