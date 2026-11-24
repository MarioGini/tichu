/// Exceptions for conditions the game expects and callers handle: a move
/// the rules do not allow, an agent with nothing legal to do. (Bugs stay
/// [Error]s and are never caught.)
library;

/// Thrown by `GameEngine.applyAction` (and the rule helpers it uses) for an
/// action the rules do not allow in the current state: not this player's
/// turn, cards not in hand, an unfulfilled wish, the wrong phase...
///
/// Code that tries candidate moves (search, rollouts) catches it to skip
/// the candidate; the authority server answers it with 400.
class IllegalActionException implements Exception {
  const IllegalActionException(this.message);

  final String message;

  @override
  String toString() => 'Illegal action: $message';
}

/// Thrown by an agent asked to act in a position where it has no legal
/// action (e.g. no legal play while passing is not allowed).
class NoLegalActionException implements Exception {
  const NoLegalActionException(this.message);

  final String message;

  @override
  String toString() => 'No legal action: $message';
}
