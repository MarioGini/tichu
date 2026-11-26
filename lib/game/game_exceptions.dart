/// Thrown by `GameEngine.applyAction` (and the rule helpers it uses) for an
/// action the rules do not allow in the current state: not this player's
/// turn, cards not in hand, an unfulfilled wish, the wrong phase...
///
/// Only moves from outside can be illegal (a person, a network client):
/// the authority server answers it with 400. Bots, searches and rollouts
/// pick from the legal moves, so for them it is a bug and is not caught.
class IllegalActionException implements Exception {
  const IllegalActionException(this.message);

  final String message;

  @override
  String toString() => 'Illegal action: $message';
}
