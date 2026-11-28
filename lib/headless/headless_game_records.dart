part of 'headless.dart';

/// Compact game records (`--record-games`): one bc-jsonl row per round
/// with the deal (all 14 cards of every seat) and every decision in order,
/// so any feature of any position can be rebuilt later by replaying the
/// round in the deterministic engine. Play rows carry `step` (the index of
/// their action in this list) to find their position again.
///
/// Action codes: `[seat, "g", call]` Grand Tichu decision, `[seat, "t"]`
/// Tichu, `[seat, "G"]` Grand Tichu call, `[seat, "s", left, partner,
/// right]` schupf (card slots), `[seat, "a"]` schupf acknowledged,
/// `[seat, "p", [slots], wish]` play (wish = CardFace index, 0 none),
/// `[seat, "x"]` pass, `[seat, "d", targetSeat]` Dragon gift, `[seat, "c"]`
/// confirm.
class _GameRecorder {
  /// Partner convention per seat (replay needs it for the features).
  final List<PartnerConvention> conventions;

  _GameRecorder({required this.conventions});

  List<List<int>>? _deal;
  final List<List<Object>> actions = [];

  int get step => actions.length;

  void startRound(GameEngineState state) {
    actions.clear();
    _deal = [
      for (final p in [...state.players]..sort((a, b) => a.seat - b.seat))
        [
          for (final c in [
            ...state.hands[p.id] ?? const <Card>[],
            ...state.reservedHands[p.id] ?? const <Card>[],
          ])
            cardSlot(c),
        ],
    ];
  }

  void add(GameEngineState state, GameAction action) {
    int seatOf(String id) => state.players.firstWhere((p) => p.id == id).seat;
    final seat = seatOf(action.playerId);
    actions.add(switch (action) {
      GrandTichuDecisionAction(:final call) => [seat, 'g', if (call) 1 else 0],
      CallTichuAction() => [seat, 't'],
      CallGrandTichuAction() => [seat, 'G'],
      SchupfAction(:final toLeft, :final toPartner, :final toRight) => [
        seat,
        's',
        cardSlot(toLeft),
        cardSlot(toPartner),
        cardSlot(toRight),
      ],
      AcknowledgeSchupfAction() => [seat, 'a'],
      PlayTurnAction(:final cards, :final inputWish) => [
        seat,
        'p',
        [for (final c in cards) cardSlot(c)],
        inputWish.index,
      ],
      PassAction() => [seat, 'x'],
      GiveDragonAction(:final targetPlayerId) => [
        seat,
        'd',
        seatOf(targetPlayerId),
      ],
      ConfirmOpponentTurnAction() => [seat, 'c'],
      _ => [seat, action.runtimeType.toString()],
    });
  }

  Map<String, Object?> record(int episode, GameSnapshot end) => {
    'episode': episode,
    'round': end.scoreState.roundNumber,
    'game_record': true,
    'deal': _deal,
    if (conventions.any((c) => c != PartnerConvention.free))
      'conventions': [for (final c in conventions) c.name],
    'actions': actions,
    'result': [end.scoreState.teamOneRound, end.scoreState.teamTwoRound],
  };
}
