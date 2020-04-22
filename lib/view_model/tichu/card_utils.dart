import 'package:tichu/view_model/tichu/tichu_data.dart';

bool canPlayCard(Card card, double value) {
  return card.index > value;
}
