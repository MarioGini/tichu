import '../services/firestore_api.dart';
import 'turn/tichu_data.dart';
import 'turn/turn_handler.dart';

class Player {
  final Player left;
  final Player partner;
  final Player right;

  List<Card> handCards;
  bool grandTichu;
  bool tichu;
  int numCards;

  int finishNumber;

  List<Card> madeCards;

  TurnHandler turnHandler;

  final StoreAPI fireStore;

  Player(this.left, this.partner, this.right, this.fireStore);
}
