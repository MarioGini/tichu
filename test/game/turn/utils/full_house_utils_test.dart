import 'package:flutter_test/flutter_test.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/utils/full_house_utils.dart';

void main() {
  group('getFullHouses', () {
    test('returnsEmptyWhenLessThanFiveCards', () {
      final cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
      ];

      final turns = getFullHouses(cards);

      expect(turns, isEmpty);
    });

    test('ignoresDragonAndDogCards', () {
      final cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.dragon, CardColor.special),
        Card(CardFace.dog, CardColor.special),
      ];

      final turns = getFullHouses(cards);

      expect(turns.length, 1);
      expect(turns.first.type, TurnType.fullHouse);
      expect(
        turns.first.cards.any(
          (card) => card.face == CardFace.dragon || card.face == CardFace.dog,
        ),
        false,
      );
    });

    test('twoTripletsTest', () {
      final cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.five, CardColor.red),
      ];

      final turns = getFullHouses(cards);

      expect(turns.length, 2);
      expect(turns.every((turn) => turn.type == TurnType.fullHouse), true);
      expect(
        turns.any((turn) => turn.value == Card.getValue(CardFace.two)),
        true,
      );
      expect(
        turns.any((turn) => turn.value == Card.getValue(CardFace.five)),
        true,
      );
    });
    test('twoPairsTest', () {
      final cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.seven, CardColor.black),
      ];

      final turns = getFullHouses(cards);

      expect(turns.length, 2);
      expect(turns.every((turn) => turn.type == TurnType.fullHouse), true);
      expect(
        turns.every((turn) => turn.value == Card.getValue(CardFace.two)),
        true,
      );
      expect(
        turns.any(
          (turn) => turn.cards.any((card) => card.face == CardFace.five),
        ),
        true,
      );
      expect(
        turns.any(
          (turn) => turn.cards.any((card) => card.face == CardFace.seven),
        ),
        true,
      );
    });
    test('twoPairsPhoenixTest', () {
      final cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.seven, CardColor.red),
        Card(CardFace.seven, CardColor.black),
      ];

      final turns = getFullHouses(cards);

      expect(turns.length, 6);
      expect(turns.every((turn) => turn.type == TurnType.fullHouse), true);
      final sevenFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.seven))
          .length;
      final fiveFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.five))
          .length;
      final twoFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.two))
          .length;
      expect(sevenFullHouseCount, 2);
      expect(fiveFullHouseCount, 2);
      expect(twoFullHouseCount, 2);
    });
    test('tripletPhoenixTest', () {
      final cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.five, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.seven, CardColor.black),
      ];

      final turns = getFullHouses(cards);

      expect(turns.length, 3);
      expect(turns.every((turn) => turn.type == TurnType.fullHouse), true);
      final fiveFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.five))
          .length;
      final twoFullHouseCount = turns
          .where((element) => element.value == Card.getValue(CardFace.two))
          .length;
      expect(fiveFullHouseCount, 1);
      expect(twoFullHouseCount, 2);
    });

    test('phoenixPromotesSingleToPair', () {
      final cards = <Card>[
        Card(CardFace.two, CardColor.black),
        Card(CardFace.two, CardColor.green),
        Card(CardFace.two, CardColor.red),
        Card(CardFace.five, CardColor.black),
        Card(CardFace.seven, CardColor.green),
        Card(CardFace.phoenix, CardColor.special),
      ];

      final turns = getFullHouses(cards);

      expect(turns.length, 2);
      expect(turns.every((turn) => turn.type == TurnType.fullHouse), true);
      expect(
        turns.every((turn) => turn.value == Card.getValue(CardFace.two)),
        true,
      );
      expect(
        turns.any(
          (turn) =>
              turn.cards.any((card) => card.face == CardFace.phoenix) &&
              turn.cards.any((card) => card.face == CardFace.five),
        ),
        true,
      );
      expect(
        turns.any(
          (turn) =>
              turn.cards.any((card) => card.face == CardFace.phoenix) &&
              turn.cards.any((card) => card.face == CardFace.seven),
        ),
        true,
      );
    });
    test('usesOnlyThreeCardsWhenTripleFaceHasFourCards', () {
      // Regression: four-of-a-kind used to be emitted whole, yielding an
      // invalid 6-card "full house" (8888 + 44) that crashed headless play.
      final cards = <Card>[
        Card(CardFace.eight, CardColor.black),
        Card(CardFace.eight, CardColor.green),
        Card(CardFace.eight, CardColor.blue),
        Card(CardFace.eight, CardColor.red),
        Card(CardFace.four, CardColor.black),
        Card(CardFace.four, CardColor.green),
      ];

      final turns = getFullHouses(cards);

      expect(turns, isNotEmpty);
      for (final turn in turns) {
        expect(turn.type, TurnType.fullHouse);
        expect(turn.cards, hasLength(5));
      }
      expect(
        turns.any(
          (t) =>
              t.cards.where((c) => c.face == CardFace.eight).length == 3 &&
              t.cards.where((c) => c.face == CardFace.four).length == 2,
        ),
        isTrue,
      );
    });

    test('the Phoenix cannot pair the Mah Jong', () {
      final turns = getFullHouses([
        Card(CardFace.mahJong, CardColor.special),
        Card(CardFace.phoenix, CardColor.special),
        Card(CardFace.king, CardColor.green),
        Card(CardFace.king, CardColor.blue),
        Card(CardFace.king, CardColor.red),
      ]);
      expect(turns, isEmpty);
    });
  });
}
