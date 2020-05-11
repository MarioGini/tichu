import 'package:cloud_firestore/cloud_firestore.dart';

import '../view_model/turn/tichu_data.dart';

class StoreAPI {
  CollectionReference collectionReference;

  StoreAPI(this.collectionReference);

  // Returns the unique uid and sets up cloud player collection.
  String registerPlayer() {
    return 'abc';
  }

  Future<List<int>> getFirstEightCards(String uid) async {
    final doc = await collectionReference.document(uid).get();

    return doc['cards'].cast<int>();
  }
}
