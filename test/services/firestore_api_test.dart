import 'package:test/test.dart';
import 'package:tichu/services/firestore_api.dart';
import 'package:cloud_firestore_mocks/cloud_firestore_mocks.dart';

void main() {
  group('storeAPI', () {
    test('test', () async {
      final instance = MockFirestoreInstance();
      final tableUid = '1';
      final playerUid = '1';

      final cardList = [4, 2, 31];
      final expectedCards =
          cardList.map((e) => StoreAPI.cardIdentifiers[e]).toList();

      await instance
          .collection('table')
          .document(tableUid)
          .collection('cards')
          .document(playerUid)
          .setData({'cards': cardList});

      final api = StoreAPI(instance);

      var cards = await api.getCards();

      expect(cards, expectedCards);
    });
  });
}
