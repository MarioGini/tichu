import 'package:test/test.dart';
import 'package:tichu/services/firestore_api.dart';
import 'package:cloud_firestore_mocks/cloud_firestore_mocks.dart';

void main() {
  group('storeAPI', () {
    test('test', () async {
      final instance = MockFirestoreInstance();
      final uid = 'abc';
      await instance.collection('cards').document(uid).setData({
        'id': uid,
        'cards': [4, 2, 3]
      });

      final api = StoreAPI(instance.collection('cards'));

      var cards = await api.getFirstEightCards(uid);

      expect(cards.length, 3);
    });
  });
}
