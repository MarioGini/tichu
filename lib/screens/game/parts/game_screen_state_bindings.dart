// ignore_for_file: unused_element

part of '../game_screen.dart';

mixin _GameScreenBindings on State<GameScreen> {
  String get _humanId;
  GameBackend get _backend;
  String? get _gameId;
  PlayerSnapshot? get _snapshot;
  List<Card> get _hand;
  Set<int> get _selectedIndexes;
  TurnHandler get _turnHandler;
  AnimationController get _bombController;

  bool get _canDeclareTichu;
  set _canDeclareTichu(bool value);

  bool get _tichuDeclared;
  set _tichuDeclared(bool value);

  bool get _roundCompleteAcknowledged;
  set _roundCompleteAcknowledged(bool value);

  int get _lastDialogRoundNumber;
  set _lastDialogRoundNumber(int value);

  bool get _dragonGiveDialogOpen;
  set _dragonGiveDialogOpen(bool value);

  bool get _grandTichuDialogOpen;
  set _grandTichuDialogOpen(bool value);

  bool get _wishDialogOpen;
  set _wishDialogOpen(bool value);

  bool get _showBombOverlay;
  set _showBombOverlay(bool value);

  String? get _lastAutoConfirmKey;
  set _lastAutoConfirmKey(String? value);

  String? get _lastAutoPassKey;
  set _lastAutoPassKey(String? value);

  double get _aiDelaySeconds;
  set _aiDelaySeconds(double value);

  bool get _autoPassEnabled;
  set _autoPassEnabled(bool value);

  Card? get _schupfToLeft;
  set _schupfToLeft(Card? value);

  Card? get _schupfToPartner;
  set _schupfToPartner(Card? value);

  Card? get _schupfToRight;
  set _schupfToRight(Card? value);

  Timer? get _autoConfirmTimer;
  set _autoConfirmTimer(Timer? value);

  bool get _schupfAckPending;
  set _schupfAckPending(bool value);

  TichuTurn? _resolveSelectedTurn(
    PlayerSnapshot snapshot, {
    bool requireBomb = false,
  });

  bool _canBombSelected(PlayerSnapshot snapshot);

  void _showSnack(String message);

  List<Card> _selectedCards();

  Future<void> _startRound();

  Future<void> _confirmAiTurn();

  Future<void> _pass();

  Future<CardFace?> _promptWish();
}
