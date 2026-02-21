import 'package:flutter/material.dart' hide Card;

import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/wish_logic.dart';
import 'package:tichu/screens/shared/keyboard_shortcuts.dart';

/// Dialog for declaring a card-face wish when playing the Mah Jong.
class WishDialog extends StatefulWidget {
  const WishDialog({super.key, this.defaultWish});

  final CardFace? defaultWish;

  @override
  State<WishDialog> createState() => _WishDialogState();
}

class _WishDialogState extends State<WishDialog> {
  static final List<CardFace> _wishChoices = <CardFace>[
    CardFace.none,
    ...CardFace.values.where(isWishableFace),
  ];

  late CardFace _selected;

  @override
  void initState() {
    super.initState();
    final def = widget.defaultWish;
    _selected = (def != null && _wishChoices.contains(def))
        ? def
        : CardFace.none;
  }

  @override
  Widget build(final BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (final node, final event) => handleDirectionalEnterKeyEvent(
      event,
      onEnter: () => Navigator.of(context).pop(_selected),
      onLeft: () {},
      onRight: () {},
    ),
    child: AlertDialog(
      title: const Text('Declare a wish'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wish: ${_labelFor(_selected)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _wishChoices
                  .map(
                    (final face) => ChoiceChip(
                      label: Text(_labelFor(face)),
                      selected: face == _selected,
                      onSelected: (_) {
                        setState(() {
                          _selected = face;
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );

  static String _labelFor(final CardFace face) {
    switch (face) {
      case CardFace.none:
        return 'No wish';
      case CardFace.ten:
        return '10';
      case CardFace.jack:
        return 'J';
      case CardFace.queen:
        return 'Q';
      case CardFace.king:
        return 'K';
      case CardFace.ace:
        return 'A';
      case CardFace.mahJong:
      case CardFace.two:
      case CardFace.three:
      case CardFace.four:
      case CardFace.five:
      case CardFace.six:
      case CardFace.seven:
      case CardFace.eight:
      case CardFace.nine:
      case CardFace.dragon:
      case CardFace.phoenix:
      case CardFace.dog:
        return Card.getValue(face).toInt().toString();
    }
  }
}
