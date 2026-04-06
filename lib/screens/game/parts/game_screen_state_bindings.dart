// ignore_for_file: unused_element, private mixin helpers used by part files

part of '../game_screen.dart';

mixin _GameScreenBindings on State<GameScreen> {
  String get _humanId;
  bool get _isSelfManual;
  String? get _gameId;
  PlayerSnapshot? get _snapshot;
  List<Card> get _hand;
  Set<int> get _selectedIndexes;
  GamePlayController get _playController;
  AnimationController get _bombController;
  bool get _roundCompleteAcknowledged;
  set _roundCompleteAcknowledged(final bool value);

  int get _lastDialogRoundNumber;
  set _lastDialogRoundNumber(final int value);

  bool get _dragonGiveDialogOpen;
  set _dragonGiveDialogOpen(final bool value);

  bool get _grandTichuDialogOpen;
  set _grandTichuDialogOpen(final bool value);

  bool get _wishDialogOpen;
  set _wishDialogOpen(final bool value);

  CardFace? get _defaultWishFaceFromSchupf;
  set _defaultWishFaceFromSchupf(final CardFace? value);

  int get _defaultWishRoundNumber;
  set _defaultWishRoundNumber(final int value);

  bool get _showBombOverlay;
  set _showBombOverlay(final bool value);

  String? get _lastAutoConfirmKey;
  set _lastAutoConfirmKey(final String? value);

  String? get _lastAutoPassKey;
  set _lastAutoPassKey(final String? value);

  double get _opponentDelaySeconds;
  set _opponentDelaySeconds(final double value);

  bool get _autoPassEnabled;
  set _autoPassEnabled(final bool value);

  bool get _soundEnabled;
  set _soundEnabled(final bool value);

  bool get _aiSuggestionEnabled;
  set _aiSuggestionEnabled(final bool value);

  bool get _aiSuggestionSelectionOwned;
  set _aiSuggestionSelectionOwned(final bool value);

  Card? get _schupfToLeft;
  set _schupfToLeft(final Card? value);

  Card? get _schupfToPartner;
  set _schupfToPartner(final Card? value);

  Card? get _schupfToRight;
  set _schupfToRight(final Card? value);

  List<Card> get _schupfSentCards;
  set _schupfSentCards(final List<Card> value);

  Timer? get _autoConfirmTimer;
  set _autoConfirmTimer(final Timer? value);

  bool get _schupfAckPending;
  set _schupfAckPending(final bool value);

  TichuTurn? _resolveSelectedTurn(final PlayerSnapshot snapshot);

  bool _canPass(final PlayerSnapshot snapshot);

  void _requestKeyboardFocus();

  void _showSnack(final String message);

  List<Card> _selectedCards();

  Future<void> _startRound();

  Future<void> _submitGameAction(final GameAction action);

  Future<void> _acknowledgeRoundSummary();

  Future<void> _setAutomatedActionDelay(final Duration delay);

  Future<void> _confirmOpponentTurn();

  Future<void> _pass();

  Future<CardFace?> _promptWish({final CardFace? defaultWish});

  Future<void> _maybeApplyAiSuggestion(final PlayerSnapshot snapshot);

  void _clearAiSuggestionSelection();
}
