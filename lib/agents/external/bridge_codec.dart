import 'package:tichu/game/turn/tichu_data.dart';

/// Text form of cards and combinations in the bot bridge protocol
/// (`doc/bot_bridge.md`).
///
/// A suit card is its rank (`2`-`9`, `T`, `J`, `Q`, `K`, `A`) followed by its
/// suit (`g` green, `b` blue, `k` black, `r` red), e.g. `Tk`. The specials
/// are `MJ` (Mah Jong), `DG` (Dog), `PH` (Phoenix) and `DR` (Dragon). A
/// Phoenix inside a combination is still `PH`; the combination's `value`
/// says what it stands for.
abstract final class BridgeCodec {
  static const Map<CardFace, String> _ranks = {
    CardFace.two: '2',
    CardFace.three: '3',
    CardFace.four: '4',
    CardFace.five: '5',
    CardFace.six: '6',
    CardFace.seven: '7',
    CardFace.eight: '8',
    CardFace.nine: '9',
    CardFace.ten: 'T',
    CardFace.jack: 'J',
    CardFace.queen: 'Q',
    CardFace.king: 'K',
    CardFace.ace: 'A',
  };
  static const Map<CardColor, String> _suits = {
    CardColor.green: 'g',
    CardColor.blue: 'b',
    CardColor.black: 'k',
    CardColor.red: 'r',
  };
  static const Map<CardFace, String> _specials = {
    CardFace.mahJong: 'MJ',
    CardFace.dog: 'DG',
    CardFace.phoenix: 'PH',
    CardFace.dragon: 'DR',
  };

  static String card(Card card) {
    final special = _specials[card.face];
    if (special != null) return special;
    return '${_ranks[card.face]}${_suits[card.color]}';
  }

  static List<String> cards(Iterable<Card> cards) => [
    for (final c in cards) card(c),
  ];

  /// The hand card written as [code] (a Phoenix comes back unvalued).
  static Card parseCard(String code) {
    for (final MapEntry(:key, :value) in _specials.entries) {
      if (value == code) {
        return key == CardFace.phoenix
            ? Card(CardFace.phoenix, CardColor.special)
            : Card(key, CardColor.special);
      }
    }
    if (code.length == 2) {
      for (final rank in _ranks.entries) {
        for (final suit in _suits.entries) {
          if (rank.value == code[0] && suit.value == code[1]) {
            return Card(rank.key, suit.key);
          }
        }
      }
    }
    throw FormatException('Not a card: $code');
  }

  /// Rank text of a wish (`2`-`A`), or null for no wish.
  static String? wish(CardFace face) => _ranks[face];

  static CardFace parseWish(String? rank) {
    if (rank == null) return CardFace.none;
    for (final MapEntry(:key, :value) in _ranks.entries) {
      if (value == rank) return key;
    }
    throw FormatException('Not a wish rank: $rank');
  }

  static const Map<TurnType, String> _types = {
    TurnType.single: 'single',
    TurnType.pair: 'pair',
    TurnType.pairStraight: 'pair_straight',
    TurnType.triplet: 'triple',
    TurnType.fullHouse: 'full_house',
    TurnType.straight: 'straight',
    TurnType.dog: 'dog',
    TurnType.bomb: 'bomb',
  };

  /// `{"cards": [...], "type": ..., "value": ...}`; value is the rank the
  /// combination is compared by (2-14, a single Phoenix half a rank above
  /// what it beat, 25 the Dragon).
  static Map<String, Object?> combo(TichuTurn turn) {
    // The move generator lists the Dog as a single.
    final dog =
        turn.cards.length == 1 && turn.cards.single.face == CardFace.dog;
    return {
      'cards': cards(turn.cards),
      'type': dog ? 'dog' : _types[turn.type] ?? 'none',
      'value': dog ? 0.0 : turn.value,
    };
  }
}
