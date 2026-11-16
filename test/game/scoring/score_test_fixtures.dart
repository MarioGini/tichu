import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/turn/tichu_data.dart';

const playerOneId = 'p1';
const playerTwoId = 'p2';
const playerThreeId = 'p3';
const playerFourId = 'p4';

final players = <GamePlayer>[
  const GamePlayer(
    id: playerOneId,
    name: 'P1',
    seat: 0,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: playerTwoId,
    name: 'P2',
    seat: 1,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: playerThreeId,
    name: 'P3',
    seat: 2,
    type: PlayerType.automated,
  ),
  const GamePlayer(
    id: playerFourId,
    name: 'P4',
    seat: 3,
    type: PlayerType.automated,
  ),
];

Card fxCard(final CardFace face, final CardColor color) => Card(face, color);

Map<String, List<Card>> handsWithLast(
  final String lastId,
  final List<Card> lastHand,
) => {
  playerOneId: const <Card>[],
  playerTwoId: const <Card>[],
  playerThreeId: const <Card>[],
  playerFourId: const <Card>[],
  lastId: lastHand,
};
