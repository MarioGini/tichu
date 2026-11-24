import 'package:tichu/game/turn/tichu_data.dart';

/// Compact log of one round, the stored form of a game record (format 2).
///
/// About 500 bytes per round instead of the ~27 KB of the event list: it
/// keeps only what cannot be derived — the deal and every action in order —
/// and the viewer ([describeRoundLog]) rebuilds hands and text by replay.
///
/// JSON: `{"n": round, "t": start, "d": deal, "m": moves, "r": [a, b]}`
///
/// * Cards are two characters: rank `2`-`9`, `T`, `J`, `Q`, `K`, `A` plus
///   colour `g`/`b`/`k`/`r`; specials `MJ`, `DR`, `DG`, `PH`. A Phoenix
///   played inside a combination carries its rank instead of `H` (`P7`).
/// * `d`: the 14 cards of seats 0-3 in turn, each starting with the 8 seen
///   before the Grand Tichu decision.
/// * `m`: space-separated actions, each starting with the seat:
///   `0G` Grand Tichu, `0T` Tichu, `0>AgDR2k` schupf (to the left, partner,
///   right), `0AgAr` play, `0MJ=5` play with a wish, `0-` pass, `0@1` gives
///   the Dragon trick to seat 1.
/// * `r`: the round's points (team one = seats 0 and 2, team two).
class RoundLog {
  RoundLog({required this.round, final DateTime? startedAt})
    : startedAt = startedAt ?? DateTime.now().toUtc();

  final int round;
  final DateTime startedAt;

  /// Cards each seat saw before the Grand Tichu decision.
  final List<List<Card>> firstCards = List.generate(4, (_) => <Card>[]);

  /// All 14 cards of each seat after the deal, once dealt.
  final List<List<Card>> fullHands = List.generate(4, (_) => <Card>[]);
  final List<String> actions = [];
  List<int>? result;

  String get dealCode {
    final out = StringBuffer();
    for (var seat = 0; seat < 4; seat++) {
      final first = firstCards[seat];
      final rest = [...fullHands[seat]];
      first.forEach(rest.remove);
      for (final c in [...first, ...rest]) {
        out.write(cardCode(c));
      }
    }
    return out.toString();
  }

  Map<String, Object?> toJson() => {
    'n': round,
    't': startedAt.toIso8601String().split('.').first,
    'd': dealCode,
    'm': actions.join(' '),
    'r': ?result,
  };
}

const Map<CardFace, String> _rankChars = {
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

/// Rank character of a face (`2`..`9`, `T`, `J`, `Q`, `K`, `A`), or null.
String? rankChar(final CardFace face) => _rankChars[face];

/// Two-character code of [card] (see [RoundLog]).
String cardCode(final Card card) => switch (card.face) {
  CardFace.mahJong => 'MJ',
  CardFace.dragon => 'DR',
  CardFace.dog => 'DG',
  CardFace.phoenix => _phoenixCode(card.value),
  CardFace.none => '??',
  _ => '${_rankChars[card.face]}${_colorChar(card.color)}',
};

String _phoenixCode(final double value) {
  if (value == value.roundToDouble() && value >= 2 && value <= 14) {
    final face = _rankChars.keys.firstWhere(
      (final f) => Card.getValue(f) == value,
    );
    return 'P${_rankChars[face]}';
  }
  return 'PH';
}

String _colorChar(final CardColor color) => switch (color) {
  CardColor.green => 'g',
  CardColor.blue => 'b',
  CardColor.black => 'k',
  CardColor.red => 'r',
  CardColor.special => '',
};

/// Readable label of a card code: `Ag`, `10r`, `MahJong`, `Phoenix`, ...
String cardCodeLabel(final String code) {
  if (code.startsWith('P')) return 'Phoenix';
  return switch (code) {
    'MJ' => 'MahJong',
    'DR' => 'Dragon',
    'DG' => 'Dog',
    _ => '${code[0] == 'T' ? '10' : code[0]}${code[1]}',
  };
}

/// Card codes in [s] (concatenated two-character codes).
List<String> splitCardCodes(final String s) => [
  for (var i = 0; i + 1 < s.length; i += 2) s.substring(i, i + 2),
];

/// One replayed action of a [RoundLog]: readable [text] and each seat's
/// hand (card codes) right after it.
class RoundLogStep {
  const RoundLogStep({
    required this.seat,
    required this.text,
    required this.hands,
  });

  final int seat;
  final String text;
  final List<List<String>> hands;
}

/// Replays a stored round ([RoundLog.toJson]) into readable steps; [names]
/// are the players by seat. Throws [FormatException] on a malformed log,
/// e.g. a card played that the seat does not hold.
List<RoundLogStep> describeRoundLog(
  final Map<String, Object?> round,
  final List<String> names,
) {
  final deal = splitCardCodes(round['d']! as String);
  if (deal.length != 56) {
    throw FormatException('deal has ${deal.length} cards, expected 56');
  }
  final hands = [
    for (var seat = 0; seat < 4; seat++)
      deal.sublist(seat * 14, seat * 14 + 14),
  ];
  String name(final int seat) => names[seat];
  final steps = <RoundLogStep>[];
  final pendingSchupf = <(int, List<String>)>[];

  void take(final int seat, final List<String> cards) {
    for (final c in cards) {
      // A Phoenix is dealt as PH and may be played with a rank (P7).
      final held = c.startsWith('P') ? 'PH' : c;
      if (!hands[seat].remove(held)) {
        throw FormatException('${name(seat)} does not hold $c');
      }
    }
  }

  final moves = (round['m'] as String? ?? '').trim();
  for (final token in moves.isEmpty ? const <String>[] : moves.split(' ')) {
    final seat = int.parse(token[0]);
    final rest = token.substring(1);
    final String text;
    if (rest == 'G') {
      text = '${name(seat)} calls GRAND TICHU';
    } else if (rest == 'T') {
      text = '${name(seat)} calls TICHU';
    } else if (rest == '-') {
      text = '${name(seat)} passes';
    } else if (rest.startsWith('@')) {
      text =
          '${name(seat)} gives the Dragon trick to '
          '${name(int.parse(rest.substring(1)))}';
    } else if (rest.startsWith('>')) {
      final cards = splitCardCodes(rest.substring(1));
      take(seat, cards);
      pendingSchupf.add((seat, cards));
      text =
          '${name(seat)} passes '
          '${[for (final c in cards) cardCodeLabel(c)].join(' ')} '
          '(left, partner, right)';
      if (pendingSchupf.length == 4) {
        for (final (from, passed) in pendingSchupf) {
          for (var i = 0; i < 3; i++) {
            hands[(from + i + 1) % 4].add(passed[i]);
          }
        }
        pendingSchupf.clear();
      }
    } else {
      final parts = rest.split('=');
      final cards = splitCardCodes(parts.first);
      take(seat, cards);
      final wish = parts.length > 1 ? ', wishes ${parts[1]}' : '';
      text =
          '${name(seat)} plays '
          '${[for (final c in cards) cardCodeLabel(c)].join(' ')}$wish'
          '${hands[seat].isEmpty ? ' and is out' : ''}';
    }
    steps.add(
      RoundLogStep(
        seat: seat,
        text: text,
        hands: [for (final h in hands) List<String>.unmodifiable(h)],
      ),
    );
  }
  return steps;
}
