import 'package:tichu/game/record/uuid.dart';
import 'package:tichu/game/turn/tichu_data.dart';

/// Minimal log of one round: the initial cards and the move order, nothing
/// that can be derived. The stored form of a game record (format 3). One
/// string per round, about 220 bytes:
///
///     <deal: 56 card chars> [calls] <schupf: 12 card chars> <moves>
///
/// * **Card chars**: one character per card. `A`-`Z`, `a`-`z` are the 52
///   suit cards, index `rank * 4 + colour` (ranks 2..A, colours g, b, k, r),
///   so `A` = 2 green, `B` = 2 blue, ... `z` = ace red; `0` MahJong, `1` Dog,
///   `2` Phoenix, `3` Dragon. A Phoenix played inside a combination is
///   written `~` plus the rank it stands for (`~T` = as a ten).
/// * **Deal**: seats 0-3, 14 cards each, the 8 seen before the Grand Tichu
///   decision first.
/// * **Calls** before the schupf: `^s` Grand Tichu, `*s` Tichu by seat `s`.
/// * **Schupf**: seats 0-3, three cards each: to the left, partner, right.
/// * **Moves** in order; the seat is implied by the turn order (replayed by
///   [replayRoundLog] exactly as the engine plays it): a play is its cards,
///   `.` a pass, `,` separates two plays in a row, `=r` after the MahJong
///   wishes rank `r` (`2`-`9`, `T`, `J`, `Q`, `K`, `A`), `<` / `>` gives the
///   Dragon trick to the opponent on the left / right, `!s` before a play
///   marks a bomb by seat `s` out of turn, `*s` a Tichu call by seat `s`.
///
/// Round points are not stored: they follow from the replay.
class RoundLog {
  RoundLog({required this.round, String? id}) : id = id ?? generateUuidV4();

  final int round;

  /// Id of this round (`tichu_round_records.id`); the first 8 characters
  /// (`short_id`) are enough to look it up.
  final String id;

  /// Round points of each team, set when the round is over.
  int? teamOnePoints;
  int? teamTwoPoints;

  bool get complete => teamOnePoints != null;

  /// Cards each seat saw before the Grand Tichu decision.
  final List<List<Card>> firstCards = List.generate(4, (_) => <Card>[]);

  /// All 14 cards of each seat after the deal, once dealt.
  final List<List<Card>> fullHands = List.generate(4, (_) => <Card>[]);

  final StringBuffer _calls = StringBuffer();
  final List<List<Card>?> _schupf = List.filled(4, null);
  final StringBuffer _moves = StringBuffer();
  bool _lastWasPlay = false;
  int _schupfCount = 0;

  /// Seat of every action in the order [replayRoundLog] yields them (calls
  /// before the schupf, the schupf by seat, then the moves). Kept in memory
  /// to check the replay; not stored.
  final List<int> actionSeats = [];

  /// Actions recorded so far (as [replayRoundLog] counts them).
  int get actionCount => actionSeats.length;

  void addGrandTichu(int seat) => addCall(seat, grand: true);

  /// A call before the play phase (Grand Tichu, or Tichu at 14 cards).
  void addCall(int seat, {required bool grand}) {
    _calls.write('${grand ? '^' : '*'}$seat');
    // Calls before the schupf replay before it.
    actionSeats.insert(actionSeats.length - _schupfCount, seat);
  }

  /// A Tichu call during the play phase.
  void addTichuDuringPlay(int seat) {
    _moves.write('*$seat');
    _lastWasPlay = false;
    actionSeats.add(seat);
  }

  void addSchupf(int seat, Card toLeft, Card toPartner, Card toRight) {
    _schupf[seat] = [toLeft, toPartner, toRight];
    _schupfCount++;
    actionSeats.add(seat);
    if (_schupfCount == 4) {
      // The replay lists the schupf by seat.
      final start = actionSeats.length - 4;
      actionSeats.replaceRange(start, actionSeats.length, [0, 1, 2, 3]);
    }
  }

  void addPlay(
    int seat,
    List<Card> cards, {
    CardFace wish = CardFace.none,
    bool outOfTurn = false,
  }) {
    if (outOfTurn) {
      _moves.write('!$seat');
    } else if (_lastWasPlay) {
      _moves.write(',');
    }
    final combination = cards.length > 1;
    for (final c in cards) {
      _moves.write(cardChar(c, inCombination: combination));
    }
    final w = _rankChars[wish];
    if (w != null) _moves.write('=$w');
    _lastWasPlay = true;
    actionSeats.add(seat);
  }

  void addPass(int seat) {
    _moves.write('.');
    _lastWasPlay = false;
    actionSeats.add(seat);
  }

  /// [toLeft]: the trick goes to the opponent on the giver's left.
  void addDragonGift(int seat, {required bool toLeft}) {
    _moves.write(toLeft ? '<' : '>');
    _lastWasPlay = false;
    actionSeats.add(seat);
  }

  String get dealCode {
    final out = StringBuffer();
    for (var seat = 0; seat < 4; seat++) {
      final first = firstCards[seat];
      final rest = [...fullHands[seat]];
      first.forEach(rest.remove);
      for (final c in [...first, ...rest]) {
        out.write(cardChar(c));
      }
    }
    return out.toString();
  }

  /// The stored string (see the class comment).
  String encode() {
    final out = StringBuffer(dealCode)..write(_calls);
    if (_schupf.every((s) => s != null)) {
      for (final s in _schupf) {
        out.writeAll(s!.map(cardChar));
      }
      out.write(_moves);
    }
    return out.toString();
  }
}

const String _cardAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123';

const List<CardFace> _rankFaces = [
  CardFace.two,
  CardFace.three,
  CardFace.four,
  CardFace.five,
  CardFace.six,
  CardFace.seven,
  CardFace.eight,
  CardFace.nine,
  CardFace.ten,
  CardFace.jack,
  CardFace.queen,
  CardFace.king,
  CardFace.ace,
];

const List<CardColor> _colors = [
  CardColor.green,
  CardColor.blue,
  CardColor.black,
  CardColor.red,
];

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

const int _mahJong = 52;
const int _dog = 53;
const int _phoenix = 54;
const int _dragon = 55;

/// Index 0-55 of [card] (see [RoundLog]).
int cardIndex(Card card) => switch (card.face) {
  CardFace.mahJong => _mahJong,
  CardFace.dog => _dog,
  CardFace.phoenix => _phoenix,
  CardFace.dragon => _dragon,
  CardFace.none => throw ArgumentError('no card'),
  _ => _rankFaces.indexOf(card.face) * 4 + _colors.indexOf(card.color),
};

/// One-character code of [card]; a Phoenix with a rank inside a combination
/// is `~` plus that rank.
String cardChar(Card card, {bool inCombination = false}) {
  if (card.face == CardFace.phoenix && inCombination) {
    final v = card.value;
    if (v == v.roundToDouble() && v >= 2 && v <= 14) {
      return '~${_rankChars[_rankFaces[v.toInt() - 2]]}';
    }
  }
  return _cardAlphabet[cardIndex(card)];
}

/// Readable label of card index [i]: `Ag`, `10r`, `MahJong`, ...
String cardIndexLabel(int i) => switch (i) {
  _mahJong => 'MahJong',
  _dog => 'Dog',
  _phoenix => 'Phoenix',
  _dragon => 'Dragon',
  _ => '${_rankLabel(_rankFaces[i ~/ 4])}${const ['g', 'b', 'k', 'r'][i % 4]}',
};

String _rankLabel(CardFace face) =>
    face == CardFace.ten ? '10' : _rankChars[face]!;

/// The 14 dealt cards (indices) of each seat in a stored round.
List<List<int>> dealtHands(String log) {
  final r = _Reader(log);
  return [
    for (var seat = 0; seat < 4; seat++)
      [for (var i = 0; i < 14; i++) r.card()],
  ];
}

/// One replayed action: its [seat], readable [text] and every seat's hand
/// (card indices) right after it.
class RoundLogStep {
  const RoundLogStep({
    required this.seat,
    required this.text,
    required this.hands,
  });

  final int seat;
  final String text;
  final List<List<int>> hands;
}

/// Replays a stored round ([RoundLog.encode]); [names] are the players by
/// seat. Seats follow the engine's turn order. Throws [FormatException] on
/// a malformed log, e.g. a card the seat does not hold.
List<RoundLogStep> replayRoundLog(String log, List<String> names) {
  final r = _Reader(log);
  final hands = List.generate(4, (_) => <int>[]);
  for (var seat = 0; seat < 4; seat++) {
    for (var i = 0; i < 14; i++) {
      hands[seat].add(r.card());
    }
  }
  final steps = <RoundLogStep>[];
  void step(int seat, String text) => steps.add(
    RoundLogStep(
      seat: seat,
      text: text,
      hands: [for (final h in hands) List<int>.unmodifiable(h)],
    ),
  );
  String labels(Iterable<int> cards) => cards.map(cardIndexLabel).join(' ');
  void take(int seat, List<int> cards) {
    for (final c in cards) {
      if (!hands[seat].remove(c)) {
        throw FormatException(
          '${names[seat]} does not hold ${cardIndexLabel(c)}',
        );
      }
    }
  }

  // Calls before the schupf.
  while (!r.done && (r.peek == '^' || r.peek == '*')) {
    final grand = r.next() == '^';
    final seat = r.seat();
    step(seat, '${names[seat]} calls ${grand ? 'GRAND TICHU' : 'TICHU'}');
  }
  if (r.done) return steps;

  // Schupf.
  final passed = [
    for (var seat = 0; seat < 4; seat++) [r.card(), r.card(), r.card()],
  ];
  for (var seat = 0; seat < 4; seat++) {
    take(seat, passed[seat]);
  }
  for (var seat = 0; seat < 4; seat++) {
    for (var i = 0; i < 3; i++) {
      hands[(seat + i + 1) % 4].add(passed[seat][i]);
    }
  }
  for (var seat = 0; seat < 4; seat++) {
    step(
      seat,
      '${names[seat]} passes ${labels(passed[seat])} (left, partner, right)',
    );
  }

  // Play, mirroring the engine's turn order (trick_resolution.dart).
  final out = <int>[];
  bool isOut(int seat) => out.contains(seat);
  int nextActive(int from) {
    var next = (from + 1) % 4;
    while (isOut(next) && next != from) {
      next = (next + 1) % 4;
    }
    return next;
  }

  var current = hands.indexWhere((h) => h.contains(_mahJong));
  int? lastPlayedBy;
  var trickOpen = false;

  while (!r.done) {
    final c = r.peek;
    if (c == '.') {
      r.next();
      final seat = current;
      step(seat, '${names[seat]} passes');
      current = nextActive(current);
      final winner = lastPlayedBy;
      if (winner != null && trickOpen) {
        final leadReturn = isOut(winner) ? nextActive(winner) : winner;
        if (current == leadReturn) trickOpen = false;
      }
    } else if (c == '<' || c == '>') {
      r.next();
      final giver = lastPlayedBy ?? current;
      final to = (giver + (c == '<' ? 1 : 3)) % 4;
      step(giver, '${names[giver]} gives the Dragon trick to ${names[to]}');
    } else if (c == '*') {
      r.next();
      final seat = r.seat();
      step(seat, '${names[seat]} calls TICHU');
    } else if (c == ',') {
      r.next();
    } else {
      if (c == '!') {
        r.next();
        current = r.seat();
      }
      final seat = current;
      final cards = <int>[];
      while (!r.done && r.isCardStart) {
        cards.add(r.card());
      }
      if (cards.isEmpty) throw FormatException('unexpected "${r.peek}"');
      var wish = '';
      if (!r.done && r.peek == '=') {
        r.next();
        wish = ', wishes ${r.next()}';
      }
      take(seat, cards);
      if (hands[seat].isEmpty) out.add(seat);
      final wentOut = hands[seat].isEmpty ? ' and is out' : '';
      step(seat, '${names[seat]} plays ${labels(cards)}$wish$wentOut');
      if (cards.length == 1 && cards.single == _dog) {
        trickOpen = false;
        lastPlayedBy = null;
        current = (current + 2) % 4;
        if (isOut(current)) current = nextActive(current);
      } else {
        trickOpen = true;
        lastPlayedBy = seat;
        current = nextActive(current);
      }
    }
  }
  return steps;
}

class _Reader {
  _Reader(this.s);

  final String s;
  int i = 0;

  bool get done => i >= s.length;
  String get peek => s[i];

  String next() {
    if (done) throw const FormatException('log ends early');
    return s[i++];
  }

  bool get isCardStart => peek == '~' || _cardAlphabet.contains(peek);

  int seat() {
    final v = int.tryParse(next());
    if (v == null || v > 3) throw const FormatException('bad seat');
    return v;
  }

  int card() {
    final c = next();
    if (c == '~') {
      final rank = next();
      if (!_rankChars.containsValue(rank)) {
        throw FormatException('bad Phoenix rank "$rank"');
      }
      return _phoenix;
    }
    final index = _cardAlphabet.indexOf(c);
    if (index < 0) throw FormatException('bad card "$c"');
    return index;
  }
}
