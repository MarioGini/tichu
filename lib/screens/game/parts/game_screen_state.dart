part of '../game_screen.dart';

/// All mutable state of the game screen. The part-file mixins below build on
/// this class; members they share with each other are declared here.
abstract class _GameScreenStateBase extends State<GameScreen>
    with TickerProviderStateMixin {
  late final String _humanId;
  PlayerControlMode _selfControlMode = PlayerControlMode.manual;

  bool get _isSelfManual => _selfControlMode == PlayerControlMode.manual;
  late final GameMatchService _matchService;
  late final GameSessionHandle _sessionHandle;
  final DriverUiProjector _uiProjector = const DriverUiProjector();
  late final GamePlayController _playController = GamePlayController();
  StreamSubscription<GameMatchView>? _matchSubscription;
  PlayerSnapshot? _snapshot;
  int? _selfSeat;
  int _matchRevision = 0;
  int _clientActionCounter = 0;

  List<Card> _hand = [];
  final Set<int> _selectedIndexes = <int>{};
  List<Card> _trickCards = <Card>[];
  List<Card> _pendingOpponentCards = <Card>[];
  bool _pendingOpponentPass = false;
  String? _pendingOpponentPlayerId;
  String? _dragonGiveKey;
  TichuTurn? _dragonGiveTurn;
  String? _gameId;
  int _lastDialogRoundNumber = 0;
  bool _roundCompleteAcknowledged = true;
  bool _showBombOverlay = false;
  late final AnimationController _bombController;
  late final Animation<Offset> _bombSlide;
  late final Animation<double> _bombScale;
  bool _dragonGiveDialogOpen = false;
  bool _grandTichuDialogOpen = false;
  bool _wishDialogOpen = false;
  CardFace? _defaultWishFaceFromSchupf;
  int _defaultWishRoundNumber = 0;
  String? _lastAutoConfirmKey;
  String? _lastAutoPassKey;
  double _opponentDelaySeconds = 2;
  bool _autoPassEnabled = true;
  bool _soundEnabled = SoundEffects.enabled;
  bool _aiSuggestionEnabled = true;
  bool _aiSuggestionSelectionOwned = false;
  Card? _schupfToLeft;
  Card? _schupfToPartner;
  Card? _schupfToRight;
  List<Card> _schupfSentCards = <Card>[];
  Timer? _autoConfirmTimer;
  bool _schupfAckPending = false;

  bool _grandTichuSelectNo = true;
  int? _schupfCursorIndex;
  final FocusNode _schupfFocusNode = FocusNode();
  late final SmartAiAgent _suggestionAgent;
  int _aiSuggestionRequestId = 0;

  @override
  void dispose() {
    unawaited(_matchSubscription?.cancel());
    final gameId = _gameId;
    if (gameId != null) {
      unawaited(
        _matchService.leaveMatch(
          gameId,
          accessToken: _sessionHandle.accessToken,
        ),
      );
    }
    _autoConfirmTimer?.cancel();
    _bombController.dispose();
    _schupfFocusNode.dispose();
    super.dispose();
  }

  // ── Implemented by the part-file mixins ─────────────────────────────────
  Future<void> _acknowledgeRoundSummary();
  Future<void> _acknowledgeSchupfReceipts();
  bool _canPass(final PlayerSnapshot snapshot);
  bool _canPlayAny(final PlayerSnapshot snapshot);
  bool _canPlaySelected(final PlayerSnapshot snapshot);
  void _clearAiSuggestionSelection();
  void _clearSchupfSlot(final SchupfSlot slot);
  Future<void> _confirmOpponentTurn();
  Future<void> _declareTichu();
  void _handleShortcutEnter();
  void _handleShortcutLeft();
  void _handleShortcutRight();
  void _handleTurnEffects(final TichuTurn? previous, final TichuTurn? current);
  bool get _hasKeyboardForSchupf;
  Future<void> _maybeApplyAiSuggestion(final PlayerSnapshot snapshot);
  void _maybeAutoConfirmOpponentTurn(final PlayerSnapshot snapshot);
  void _maybeAutoPass(final PlayerSnapshot snapshot);
  void _maybeAutoSelectFinisher(final PlayerSnapshot snapshot);
  void _maybeShowDragonGiveDialog(final PlayerSnapshot snapshot);
  void _maybeShowRoundCompleteDialog(final PlayerSnapshot snapshot);
  Future<void> _pass();
  Future<void> _playBomb();
  Future<void> _playSelected();
  GamePlayer? _playerForRelativeSeat(
    final PlayerSnapshot? snapshot,
    final int seatOffset,
  );
  Future<CardFace?> _promptWish({final CardFace? defaultWish});
  void _requestKeyboardFocus();
  TichuTurn? _resolveSelectedTurn(final PlayerSnapshot snapshot);
  int? _resolveSelfSeat(final PlayerSnapshot? snapshot);
  Future<void> _setAutomatedActionDelay(final Duration delay);
  void _setSchupfSlot(final SchupfSlot slot, final Card card);
  bool _shouldShowGrandTichuDecision(final PlayerSnapshot snapshot);
  Future<void> _showOptionsDialog();
  void _showSnack(final String message);
  Future<void> _startRound();
  Future<void> _submitGameAction(final GameAction action);
  Future<void> _submitGrandTichuDecision(final bool call);
  Future<void> _submitSchupf();
  void _syncSchupfCursor({required final bool defaultToRightMost});
  void _toggleSelect(final int index);
}
