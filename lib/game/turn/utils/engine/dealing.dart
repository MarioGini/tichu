import 'dart:math';

import 'package:tichu/game/game_backend.dart';
import 'package:tichu/game/turn/tichu_data.dart';

(Map<String, List<Card>> hands, Map<String, List<Card>> reserved)
dealInitialHands(final List<GamePlayer> players, final Random random) {
  final deckCards = cardIdentifiers.values.toList();
  deckCards.shuffle(random);

  final hands = <String, List<Card>>{};
  final reserved = <String, List<Card>>{};
  for (var i = 0; i < players.length; i++) {
    final start = i * 14;
    hands[players[i].id] = deckCards.sublist(start, start + 8).toList();
    reserved[players[i].id] = deckCards.sublist(start + 8, start + 14).toList();
  }

  return (hands, reserved);
}
