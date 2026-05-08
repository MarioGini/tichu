import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/wish_logic.dart';

class LegalPlayGuard {
  const LegalPlayGuard._();

  /// Filter ``candidates`` down to the strictly-legal subset.
  ///
  /// Use this when ``candidates`` is **untrusted** (came from another agent,
  /// disk, the network, etc.). Each candidate is fully re-validated:
  /// hand-containment, normalisation via [getTurn], wish enforcement, and
  /// [validTurn] against the deck.
  ///
  /// When the candidates already come from [generateLegalTurns] you should
  /// prefer [filterMoveGeneratorTurns] which skips the redundant
  /// re-normalisation and hand-containment check (they are guaranteed by
  /// construction). That fast-path is ~3-4× cheaper per decision.
  static List<TichuTurn> strictLegalTurnsFromCandidates({
    required final DeckState deck,
    required final List<Card> hand,
    required final Iterable<TichuTurn> candidates,
  }) => candidates
      .where(
        (final turn) => isStrictlyLegalTurn(deck: deck, hand: hand, turn: turn),
      )
      .toList(growable: false);

  /// Fast-path filter for turns produced by [generateLegalTurns]. Skips the
  /// re-normalisation and hand-containment checks that
  /// [strictLegalTurnsFromCandidates] performs, keeping only the wish
  /// enforcement check ([mahJong]) which the move generator does not apply.
  static List<TichuTurn> filterMoveGeneratorTurns({
    required final DeckState deck,
    required final List<Card> hand,
    required final List<TichuTurn> moveGeneratorTurns,
  }) {
    if (moveGeneratorTurns.isEmpty) return moveGeneratorTurns;
    // Wish enforcement only matters when there is an active wish on the deck.
    // mahJong() returns false when there's no active wish, regardless of the
    // turn — so when the deck has no wish we can skip the per-turn check.
    if (deck.wish == CardFace.none) {
      return moveGeneratorTurns;
    }
    return moveGeneratorTurns
        .where((final turn) => !mahJong(deck, turn, hand))
        .toList(growable: false);
  }

  static bool isStrictlyLegalTurn({
    required final DeckState deck,
    required final List<Card> hand,
    required final TichuTurn turn,
  }) {
    if (turn.cards.isEmpty) {
      return false;
    }
    if (!_handContainsAll(hand, turn.cards)) {
      return false;
    }

    late final TichuTurn normalized;
    try {
      normalized = getTurn(List<Card>.from(turn.cards));
    } on Exception {
      return false;
    }

    if (normalized.type == TurnType.none) {
      return false;
    }
    if (mahJong(deck, normalized, hand)) {
      return false;
    }

    return validTurn(deck.turn, normalized);
  }

  static bool canPass({
    required final DeckState deck,
    required final List<Card> hand,
  }) {
    if (deck.turn.type == TurnType.empty || deck.turn.type == TurnType.none) {
      return false;
    }
    return !mahJong(deck, TichuTurn(TurnType.none, const []), hand);
  }

  static TichuTurn? firstLegalTurnBruteForce({
    required final DeckState deck,
    required final List<Card> hand,
  }) {
    if (hand.isEmpty) {
      return null;
    }

    for (var size = 1; size <= hand.length; size++) {
      final cards = _findPlayableOfSize(deck: deck, hand: hand, size: size);
      if (cards == null) {
        continue;
      }
      try {
        final turn = getTurn(List<Card>.from(cards));
        if (turn.type != TurnType.none) {
          return turn;
        }
      } on Exception {
        // Continue searching for another candidate subset.
      }
    }

    return null;
  }

  static List<Card>? _findPlayableOfSize({
    required final DeckState deck,
    required final List<Card> hand,
    required final int size,
  }) {
    final chosen = <Card>[];

    List<Card>? search(final int startIndex) {
      if (chosen.length == size) {
        final candidate = List<Card>.from(chosen);
        late final TichuTurn turn;
        try {
          turn = getTurn(List<Card>.from(candidate));
        } on Exception {
          return null;
        }

        if (turn.type == TurnType.none) {
          return null;
        }
        if (mahJong(deck, turn, hand)) {
          return null;
        }
        if (!validTurn(deck.turn, turn)) {
          return null;
        }

        return candidate;
      }

      for (var i = startIndex; i < hand.length; i++) {
        chosen.add(hand[i]);
        final found = search(i + 1);
        if (found != null) {
          return found;
        }
        chosen.removeLast();
      }

      return null;
    }

    return search(0);
  }

  static bool _handContainsAll(final List<Card> hand, final List<Card> cards) {
    final temp = List<Card>.from(hand);
    for (final card in cards) {
      final index = temp.indexWhere((final candidate) {
        if (card.face == CardFace.phoenix) {
          return candidate.face == CardFace.phoenix;
        }
        return candidate.face == card.face && candidate.color == card.color;
      });
      if (index == -1) {
        return false;
      }
      temp.removeAt(index);
    }
    return true;
  }
}
