import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Routes Enter / ArrowLeft / ArrowRight key-down events to callbacks.
///
/// Use as the `onKeyEvent` of a [Focus] widget to get reliable,
/// focus-independent keyboard handling (no [Shortcuts]/[Actions] layer).
///
/// Returns [KeyEventResult.handled] when a matching key is consumed,
/// [KeyEventResult.ignored] otherwise.
KeyEventResult handleDirectionalEnterKeyEvent(
  final KeyEvent event, {
  required final VoidCallback onEnter,
  required final VoidCallback onLeft,
  required final VoidCallback onRight,
}) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    onEnter();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowLeft) {
    onLeft();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowRight) {
    onRight();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
