import 'package:flutter/material.dart';

/// Suppresses RenderFlex overflow errors during a test.
/// Call in the test body before pumping widgets with tight layout.
void suppressOverflowErrors(
  void Function(FlutterErrorDetails)? previousOnError,
) {
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed')) return;
    previousOnError?.call(details);
  };
}
