import 'package:tichu/agents/external/bridge_codec.dart';
import 'package:tichu/agents/legal_play_guard.dart';
import 'package:tichu/game/game_actions.dart';
import 'package:tichu/game/game_observer.dart';
import 'package:tichu/game/game_snapshot.dart';
import 'package:tichu/game/game_types.dart';
import 'package:tichu/game/player_agent.dart';
import 'package:tichu/game/scoring/score_state.dart';
import 'package:tichu/game/turn/find_turn.dart';
import 'package:tichu/game/turn/move_generator.dart';
import 'package:tichu/game/turn/tichu_data.dart';
import 'package:tichu/game/turn/turn_handler.dart';
import 'package:tichu/game/turn/utils/bomb_utils.dart';

/// Sends one request of the bot bridge protocol and returns the reply.
abstract interface class BotChannel {
  Future<Map<String, Object?>> request(Map<String, Object?> message);
}

/// A seat played by a bot outside this program, over the bot bridge
/// protocol (`doc/bot_bridge.md`).
///
/// Every request carries what the seat has seen of the round so far: its
/// hand, the public state and the round's events from this seat's point of
/// view (other seats' passed cards stay hidden). The agent learns the events
/// by observing every applied action ([GameObserver]).
///
/// The external bot chooses among the legal options it is sent, so its
/// answer is always legal; an answer outside them is a bug in its adapter
/// and throws.
class ExternalBotAgent extends PlayerAgent implements GameObserver {
  ExternalBotAgent({
    required this.playerId,
    required this.seat,
    required this.channel,
  });

  @override
  final String playerId;
  final int seat;
  final BotChannel channel;

  final List<Map<String, Object?>> _events = [];
  List<Card> _firstCards = const [];
  List<Card>? _dealtCards;
  final Map<int, SchupfAction> _schupfs = {};

  int _seatOf(GameSnapshot s, String id) =>
      s.players.firstWhere((p) => p.id == id).seat;

  @override
  void roundStarted(GameSnapshot snapshot) {
    _events
      ..clear()
      ..add({
        'e': 'round',
        'round': snapshot.scoreState.roundNumber,
        'scores': [
          snapshot.scoreState.teamOneTotal,
          snapshot.scoreState.teamTwoTotal,
        ],
      });
    _firstCards = List.of(snapshot.hands[playerId] ?? const <Card>[]);
    _dealtCards = null;
    _schupfs.clear();
  }

  @override
  void actionApplied(
    GameAction action,
    GameSnapshot before,
    GameSnapshot after,
  ) {
    final actor = _seatOf(before, action.playerId);
    if (_dealtCards == null && after.phase != GamePhase.grandTichu) {
      _dealtCards = List.of(after.hands[playerId] ?? const <Card>[]);
    }
    switch (action) {
      case GrandTichuDecisionAction(:final call):
        _events.add({'e': 'grand', 'seat': actor, 'call': call});
      case CallGrandTichuAction():
        _events.add({'e': 'grand', 'seat': actor, 'call': true});
      case CallTichuAction():
        _events.add({'e': 'tichu', 'seat': actor});
      case SchupfAction():
        _schupfs[actor] = action;
        _events.add({
          'e': 'schupf',
          'seat': actor,
          if (actor == seat) 'give': _gifts(action, actor),
        });
        if (_schupfs.length == 4) {
          _events.add({'e': 'schupf_received', 'from': _received()});
        }
      case PlayTurnAction(:final cards, :final inputWish):
        _events.add({
          'e': 'play',
          'seat': actor,
          ...BridgeCodec.combo(getTurn(List.of(cards))),
          'wish': ?BridgeCodec.wish(inputWish),
        });
      case PassAction():
        _events.add({'e': 'pass', 'seat': actor});
      case GiveDragonAction(:final targetPlayerId):
        _events.add({
          'e': 'dragon',
          'seat': actor,
          'to': _seatOf(before, targetPlayerId),
        });
      case _:
      // Schupf acknowledgements and confirmations carry no information.
    }
  }

  /// The three passed cards by receiving seat.
  static Map<String, String> _gifts(SchupfAction a, int from) => {
    '${(from + 1) % 4}': BridgeCodec.card(a.toLeft),
    '${(from + 2) % 4}': BridgeCodec.card(a.toPartner),
    '${(from + 3) % 4}': BridgeCodec.card(a.toRight),
  };

  Map<String, String> _received() => {
    for (final MapEntry(key: from, value: a) in _schupfs.entries)
      if (from != seat) '$from': _gifts(a, from)['$seat']!,
  };

  Map<String, Object?> _state(GameSnapshot s) {
    final bySeat = [...s.players]..sort((a, b) => a.seat - b.seat);
    String call(GamePlayer p) =>
        switch (s.scoreState.tichuCalls[p.id] ?? TichuCall.none) {
          TichuCall.none => 'none',
          TichuCall.tichu => 'tichu',
          TichuCall.grandTichu => 'grand',
        };
    final trick = s.deck.turn;
    final leading = trick.type == TurnType.empty || trick.type == TurnType.none;
    return {
      'seat': seat,
      'hand': BridgeCodec.cards(s.hands[playerId] ?? const <Card>[]),
      'first_cards': BridgeCodec.cards(_firstCards),
      if (_dealtCards case final dealt?) 'dealt': BridgeCodec.cards(dealt),
      'hand_counts': [
        for (final p in bySeat) (s.hands[p.id] ?? const []).length,
      ],
      'calls': [for (final p in bySeat) call(p)],
      'trick': leading
          ? null
          : {
              ...BridgeCodec.combo(trick),
              'winner': s.deck.currentWinner.isEmpty
                  ? null
                  : _seatOf(s, s.deck.currentWinner),
            },
      'wish': BridgeCodec.wish(s.activeWish),
      'finished': [for (final id in s.scoreState.finishOrder) _seatOf(s, id)],
      'scores': [s.scoreState.teamOneTotal, s.scoreState.teamTwoTotal],
      'target_score': s.scoreState.targetScore,
      'events': List.of(_events),
    };
  }

  Future<Map<String, Object?>> _ask(
    String type,
    GameSnapshot snapshot, [
    Map<String, Object?> extra = const {},
  ]) => channel.request({'type': type, 'state': _state(snapshot), ...extra});

  @override
  Future<bool> shouldCallGrandTichu(GameSnapshot snapshot) async =>
      (await _ask('grand', snapshot))['call']! as bool;

  @override
  Future<bool> shouldCallTichuBeforeSchupf(GameSnapshot snapshot) async =>
      (await _ask('tichu', snapshot, {'phase': 'schupf'}))['call']! as bool;

  @override
  Future<bool> shouldCallTichu(GameSnapshot snapshot) async =>
      (await _ask('tichu', snapshot, {'phase': 'play'}))['call']! as bool;

  @override
  Future<SchupfAction> selectSchupfCards(GameSnapshot snapshot) async {
    final reply = await _ask('schupf', snapshot);
    final give = Map<String, Object?>.from(reply['give']! as Map);
    final hand = snapshot.hands[playerId] ?? const <Card>[];
    Card cardFor(int to) {
      final card = BridgeCodec.parseCard(give['${(seat + to) % 4}']! as String);
      if (!hand.contains(card)) {
        throw StateError('External bot passed $card, not in hand $hand.');
      }
      return card;
    }

    final action = SchupfAction(
      playerId: playerId,
      toLeft: cardFor(1),
      toPartner: cardFor(2),
      toRight: cardFor(3),
    );
    if ({action.toLeft, action.toPartner, action.toRight}.length != 3) {
      throw StateError('External bot passed a card twice: $give.');
    }
    return action;
  }

  @override
  Future<GameAction> selectTurn(GameSnapshot snapshot) async {
    final hand = List<Card>.from(snapshot.hands[playerId] ?? const <Card>[]);
    final options = LegalPlayGuard.filterMoveGeneratorTurns(
      deck: snapshot.deck,
      hand: hand,
      moveGeneratorTurns: [
        ...generateLegalTurns(snapshot.deck, List.of(hand)),
        // Our bots never split a straight flush; other bots may.
        for (final bomb in shorterStraightFlushBombs(hand))
          if (validTurn(snapshot.deck.turn, bomb)) bomb,
      ],
    );
    final canPass = LegalPlayGuard.canPass(deck: snapshot.deck, hand: hand);
    final reply = await _ask('play', snapshot, {
      'options': [for (final t in options) BridgeCodec.combo(t)],
      'can_pass': canPass,
    });
    final index = reply['option'] as int?;
    if (index == null) {
      if (!canPass) throw StateError('External bot passed when it must play.');
      return PassAction(playerId: playerId);
    }
    final turn = options[index];
    final wish = BridgeCodec.parseWish(reply['wish'] as String?);
    if (wish != CardFace.none &&
        !turn.cards.any((c) => c.face == CardFace.mahJong)) {
      throw StateError('External bot wished without playing the Mah Jong.');
    }
    return PlayTurnAction(
      playerId: playerId,
      cards: List.of(turn.cards),
      inputWish: wish,
    );
  }

  @override
  Future<int> selectDragonGive(GameSnapshot snapshot) async {
    final reply = await _ask('dragon', snapshot, {
      'targets': [
        for (final id in snapshot.pendingDragonGiveTargets)
          _seatOf(snapshot, id),
      ],
    });
    return reply['to']! as int;
  }
}
