import 'package:flutter/material.dart' hide Card;

import 'package:tichu/game/turn/tichu_data.dart';

class CardValueChip extends StatelessWidget {
  const CardValueChip({
    super.key,
    required this.text,
    this.scale = 1.0,
    this.textColor = Colors.orangeAccent,
  });

  final String text;
  final double scale;
  final Color textColor;

  @override
  Widget build(final BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(6 * scale),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: textColor,
        fontWeight: FontWeight.bold,
        fontSize: 13 * scale,
      ),
    ),
  );
}

class CardWidget extends StatelessWidget {
  const CardWidget({
    super.key,
    required this.card,
    required this.isSelected,
    this.onTap,
    this.compact = false,
    this.scale = 1.0,
    this.overlayChipText,
  });

  static const double normalWidth = 112;
  static const double normalHeight = 160;
  static const double compactWidth = 88;
  static const double compactHeight = 120;
  static bool _assetsPrecached = false;

  static Future<void> precacheCardAssets(final BuildContext context) async {
    if (_assetsPrecached) return;
    _assetsPrecached = true;

    const colors = ['black', 'blue', 'green', 'red'];
    const faces = [
      '01',
      '02',
      '03',
      '04',
      '05',
      '06',
      '07',
      '08',
      '09',
      '10',
      '11',
      '12',
      '13',
    ];

    final assetPaths = <String>[
      for (final color in colors)
        for (final face in faces) 'assets/cards/${color}_$face.png',
      'assets/cards/special_mahjong.png',
      'assets/cards/special_dragon.png',
      'assets/cards/special_phoenix.png',
      'assets/cards/special_dog.png',
    ];

    for (final path in assetPaths) {
      try {
        await precacheImage(AssetImage(path), context);
      } on Object {
        // Ignore missing/failed assets to keep startup resilient.
      }
    }
  }

  final Card card;
  final bool isSelected;
  final VoidCallback? onTap;
  final bool compact;
  final double scale;
  final String? overlayChipText;

  @override
  Widget build(final BuildContext context) {
    final label = _cardLabel(card);
    final background = card.color == CardColor.special
        ? Colors.grey.shade800
        : const Color(0xFF1B1F24);
    final assetPath = _cardAssetPath(card);

    final sizeScale = scale.clamp(0.35, 1.2);
    final width = (compact ? compactWidth : normalWidth) * sizeScale;
    final height = (compact ? compactHeight : normalHeight) * sizeScale;
    final cornerRadius = 10 * sizeScale;
    final innerRadius = 8 * sizeScale;
    final fontSize = (compact ? 12 : 16) * sizeScale;
    final selectionLift = 8 * sizeScale;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      transform: Matrix4.translationValues(
        0,
        isSelected ? -selectionLift : 0,
        0,
      ),
      child: InkWell(
        onTap: onTap,
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(cornerRadius),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [background, background.withValues(alpha: 0.75)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(cornerRadius),
            border: Border.all(
              color: isSelected ? Colors.amber : Colors.white24,
              width: isSelected ? 2 * sizeScale : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isSelected ? 0.4 : 0.25),
                blurRadius: isSelected ? 10 * sizeScale : 6 * sizeScale,
                offset: Offset(0, (isSelected ? 5 : 3) * sizeScale),
              ),
            ],
          ),
          alignment: Alignment.topCenter,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(innerRadius),
            child: Stack(
              children: [
                if (assetPath == null)
                  Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Image(
                    image: AssetImage(assetPath),
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                    errorBuilder:
                        (final context, final error, final stackTrace) => Align(
                          alignment: Alignment.topCenter,
                          child: Text(
                            label,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: fontSize,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                  ),
                if (_showOverlayChip)
                  Positioned(
                    bottom: 4 * sizeScale,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: CardValueChip(
                        text: _overlayChipLabel,
                        scale: sizeScale * 0.85,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _isPhoenixWithValue =>
      card.face == CardFace.phoenix && card.value > 0;

  bool get _showOverlayChip =>
      (overlayChipText != null && overlayChipText!.isNotEmpty) ||
      _isPhoenixWithValue;

  String get _overlayChipLabel => overlayChipText ?? _phoenixValueLabel;

  String get _phoenixValueLabel {
    final v = card.value;
    if (v % 1 == 0.5) {
      return '${_rankLabel(v.floor())}+';
    }
    return _rankLabel(v.round());
  }

  String _rankLabel(final int value) => switch (value) {
    11 => 'J',
    12 => 'Q',
    13 => 'K',
    14 => 'A',
    _ => value.toString(),
  };

  String _cardLabel(final Card card) => switch (card.face) {
    CardFace.mahJong => 'MJ',
    CardFace.dragon => 'DR',
    CardFace.phoenix => 'PH',
    CardFace.dog => 'DG',
    CardFace.jack => 'J',
    CardFace.queen => 'Q',
    CardFace.king => 'K',
    CardFace.ace => 'A',
    CardFace.ten => '10',
    CardFace.nine => '9',
    CardFace.eight => '8',
    CardFace.seven => '7',
    CardFace.six => '6',
    CardFace.five => '5',
    CardFace.four => '4',
    CardFace.three => '3',
    CardFace.two => '2',
    CardFace.none => '?',
  };

  String? _cardAssetPath(final Card card) {
    if (card.face == CardFace.none) {
      return null;
    }

    if (card.color == CardColor.special) {
      return switch (card.face) {
        CardFace.mahJong => 'assets/cards/special_mahjong.png',
        CardFace.dragon => 'assets/cards/special_dragon.png',
        CardFace.phoenix => 'assets/cards/special_phoenix.png',
        CardFace.dog => 'assets/cards/special_dog.png',
        _ => null,
      };
    }

    final faceName = _cardFaceName(card.face);
    if (faceName == null) {
      return null;
    }

    return 'assets/cards/${card.color.name}_$faceName.png';
  }

  String? _cardFaceName(final CardFace face) => switch (face) {
    CardFace.two => '02',
    CardFace.three => '03',
    CardFace.four => '04',
    CardFace.five => '05',
    CardFace.six => '06',
    CardFace.seven => '07',
    CardFace.eight => '08',
    CardFace.nine => '09',
    CardFace.ten => '10',
    CardFace.jack => '11',
    CardFace.queen => '12',
    CardFace.king => '13',
    CardFace.ace => '01',
    _ => null,
  };
}
