import 'package:flutter/material.dart' hide Card;

import '../view_model/turn/tichu_data.dart';
import 'card_widget.dart';

class HandDisplay extends StatefulWidget {
  const HandDisplay({
    super.key,
    required this.cards,
    required this.selectedIndexes,
    required this.onCardTap,
    this.targetHeight,
  });

  final List<Card> cards;
  final Set<int> selectedIndexes;
  final ValueChanged<int> onCardTap;
  final double? targetHeight;

  @override
  State<HandDisplay> createState() => _HandDisplayState();
}

class _HandDisplayState extends State<HandDisplay> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final resolvedHeight =
        widget.targetHeight ?? (screenHeight * 0.22).clamp(110.0, 160.0);
    final scale = (resolvedHeight - 16) / CardWidget.normalHeight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: SizedBox(
        height: resolvedHeight,
        child: Scrollbar(
          thumbVisibility: true,
          controller: _scrollController,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: widget.cards.length,
            itemBuilder: (context, index) {
              return CardWidget(
                card: widget.cards[index],
                isSelected: widget.selectedIndexes.contains(index),
                onTap: () => widget.onCardTap(index),
                scale: scale,
              );
            },
          ),
        ),
      ),
    );
  }
}
