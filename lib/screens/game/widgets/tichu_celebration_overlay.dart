import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tichu/screens/game/widgets/trick_event_overlay.dart';

/// Full-screen celebration overlay shown when a Tichu call succeeds,
/// before navigating to the round summary.
class TichuCelebrationOverlay extends StatefulWidget {
  const TichuCelebrationOverlay({
    super.key,
    required this.message,
    this.label = 'TICHU',
    this.isPositive = true,
  });

  final String message;
  final String label;
  final bool isPositive;

  @override
  State<TichuCelebrationOverlay> createState() =>
      _TichuCelebrationOverlayState();
}

class _TichuCelebrationOverlayState extends State<TichuCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _slide = Tween<Offset>(begin: const Offset(0, -1.6), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeInCubic,
            reverseCurve: Curves.easeIn,
          ),
        );
    _scale = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );
    unawaited(_controller.forward());
  }

  void _dismiss() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) => Material(
    color: Colors.transparent,
    child: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EventSlamOverlay(
              slide: _slide,
              scale: _scale,
              icon: widget.isPositive
                  ? Icons.emoji_events
                  : Icons.warning_amber,
              label: widget.label,
              gradientColors: widget.isPositive
                  ? [
                      Colors.orangeAccent,
                      Colors.deepOrange.shade700,
                      Colors.black87,
                    ]
                  : [Colors.pinkAccent, Colors.red.shade800, Colors.black87],
            ),
            const SizedBox(height: 6),
            Text(
              widget.message,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: widget.isPositive ? Colors.white : Colors.red.shade100,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: _dismiss, child: const Text('Next')),
          ],
        ),
      ),
    ),
  );
}
