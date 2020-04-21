import 'package:tichu/view_model/tichu/tichu_data.dart';

int countOccurrence(List<Card> cards, Card card) {
  int count = 0;
  cards.forEach((element) {
    if (element == card) {
      ++count;
    }
  });

  return count;
}
