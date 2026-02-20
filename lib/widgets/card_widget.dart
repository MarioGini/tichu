import 'package:flutter/material.dart' hide Card;

import '../game/turn/tichu_data.dart';

class CardWidget extends StatelessWidget {
  const CardWidget({
    super.key,
    required this.card,
    required this.isSelected,
    this.onTap,
    this.compact = false,
    this.scale = 1.0,
  });

  static const double normalWidth = 112;
  static const double normalHeight = 160;
  static const double compactWidth = 88;
  static const double compactHeight = 120;

  final Card card;
  final bool isSelected;
  final VoidCallback? onTap;
  final bool compact;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final color = _cardColor(card.color);
    final label = _cardLabel(card);
    final background = card.color == CardColor.special
        ? Colors.grey.shade800
        : color.withValues(alpha: 0.9);
    final assetPath = _cardAssetPath(card);

    final sizeScale = scale.clamp(0.7, 1.2);
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
                  Image.asset(
                    assetPath,
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (context, error, stackTrace) {
                      return Align(
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
                      );
                    },
                  ),
                if (_isPhoenixWithValue)
                  Positioned(
                    bottom: 4 * sizeScale,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6 * sizeScale,
                          vertical: 2 * sizeScale,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6 * sizeScale),
                        ),
                        child: Text(
                          _phoenixValueLabel,
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: fontSize * 0.85,
                          ),
                        ),
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

  String get _phoenixValueLabel {
    final v = card.value;
    if (v % 1 == 0.5) {
      return '${_rankLabel(v.floor())}+';
    }
    return _rankLabel(v.round());
  }

  String _rankLabel(int value) {
    return switch (value) {
      11 => 'J',
      12 => 'Q',
      13 => 'K',
      14 => 'A',
      _ => value.toString(),
    };
  }

  String _cardLabel(Card card) {
    return switch (card.face) {
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
  }

  String? _cardAssetPath(Card card) {
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

  String? _cardFaceName(CardFace face) {
    return switch (face) {
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
}

Color _cardColor(CardColor color) {
  return switch (color) {
    CardColor.black => const Color(0xFF2D2D2D),
    CardColor.green => const Color(0xFF2E7D32),
    CardColor.red => const Color(0xFFB71C1C),
    CardColor.blue => const Color(0xFF0D47A1),
    CardColor.special => const Color(0xFF4E4E4E),
  };
}
