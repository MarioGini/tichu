import '../turn/tichu_data.dart';

class SchupfSelection {
  final Card fromLeft;
  final Card fromPartner;
  final Card fromRight;

  SchupfSelection(this.fromLeft, this.fromPartner, this.fromRight);
}

class SchupfSend {
  final Card toLeft;
  final Card toPartner;
  final Card toRight;

  SchupfSend(this.toLeft, this.toPartner, this.toRight);
}
