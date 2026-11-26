# Bot bridge: playing other people's Tichu bots

The headless runner can give the opponent team (odd seats; even seats with
`--swap-teams`) to a bot outside this program:

```
dart run lib/headless/headless.dart --opponent-external="python3 arena/adapters/random_bot.py" ...
rl/.venv/bin/python rl/duel.py --b='--opponent-external=python3 arena/adapters/random_bot.py'
```

Our engine stays the rules authority. The external bot runs as a child
process. It reads one JSON request per line on stdin and answers each with
one JSON line on stdout, echoing the request's `id`. Its stderr is passed
through. One process serves both seats of its team. It gets one request at
a time, and every request names the seat that has to decide.

The adapter for a bot (`arena/adapters/`) translates the requests into that
bot's own game model. Usually it replays `state.events` into the bot's
engine (a shadow game) and asks the bot for its move.

## Seats

Seats are `0`-`3`. Play goes from seat `s` to seat `(s + 1) % 4`; the
partner of `s` is `(s + 2) % 4`. Teams: seats 0/2 (team 0) and 1/3 (team 1).
Every seat number in the protocol is absolute.

## Cards

A suit card is its rank, `2`-`9`, `T`, `J`, `Q`, `K` or `A`, followed by its
suit: `g` green, `b` blue, `k` black or `r` red. For example `Tk` is the
black ten. The specials are `MJ` Mah Jong, `DG` Dog, `PH` Phoenix and
`DR` Dragon.

A combination is `{"cards": [...], "type": T, "value": v}`:

- `T` is one of `single`, `pair`, `pair_straight`, `triple`, `full_house`,
  `straight`, `dog` or `bomb`. A bomb is four of a kind or a straight flush.
- `v` is the rank the combination is compared by. A single Phoenix is half a
  rank above the card it beat (1.5 when led). The Dragon is 25.

## Requests

Every request has `id`, `type` and `state`:

| field | |
|---|---|
| `seat` | the seat that decides |
| `hand` | its cards now |
| `first_cards` | its first 8 cards of the round (the Grand Tichu hand) |
| `dealt` | its 14 cards before the pass; absent during the Grand Tichu calls |
| `hand_counts` | cards held, by seat |
| `calls` | `none`, `tichu` or `grand`, by seat |
| `trick` | the combination on the table plus its `winner` (seat), or null when the seat leads |
| `wish` | the open Mah Jong wish (rank) or null |
| `finished` | seats that are out, in order |
| `scores` | game totals of team 0 and team 1 before this round |
| `target_score` | points to win the game (1000) |
| `events` | this round so far, as this seat saw it (below) |

The events, in order:

| event | |
|---|---|
| `{"e": "round", "round": n, "scores": [a, b]}` | always first |
| `{"e": "grand", "seat": s, "call": bool}` | Grand Tichu decision |
| `{"e": "tichu", "seat": s}` | Tichu call (before the pass or during play) |
| `{"e": "schupf", "seat": s, "give": {"seat": card, ...}}` | seat `s` passed; `give` only for your own seat |
| `{"e": "schupf_received", "from": {"seat": card, ...}}` | after the fourth pass: what you got |
| `{"e": "play", "seat": s, "cards", "type", "value", "wish"?}` | a play; `wish` (rank) when the Mah Jong wished |
| `{"e": "pass", "seat": s}` | a pass |
| `{"e": "dragon", "seat": s, "to": t}` | the Dragon trick given to `t` |

Tricks ending and players going out are not events. They follow from the
rules: a trick ends when everyone still holding cards has passed after the
last play, and the Dog hands the lead to the partner.

Decisions:

| `type` | extra fields | reply |
|---|---|---|
| `grand` | | `{"call": bool}` |
| `tichu` | `phase`: `schupf` (before passing) or `play` (before your play) | `{"call": bool}` |
| `schupf` | | `{"give": {"<seat>": card, ...}}` (three other seats, three different cards) |
| `play` | `options`: legal combinations, `can_pass` | `{"option": i}` (index into `options`) or `{"option": null}` to pass; `"wish": rank` or null when the chosen play holds the Mah Jong |
| `dragon` | `targets`: opponent seats | `{"to": seat}` |

A `play` request is a turn in play order. `options` lists every legal
play, bombs included, with the wish already enforced. During play a `tichu`
request comes just before each `play` request while the seat could still
call Tichu.

An adapter that fails answers `{"id": id, "error": "..."}`. The match
stops: an answer outside the options is a bug, never a move to correct.

## Rules the bridge does not model

- **Bombs out of turn.** You bomb when it is your turn, just as our bots do
  (`AgentDecisions`). A bot whose own engine offers out-of-turn bombs gets
  the same bomb offered on its next turn instead.
- **Tichu timing.** Our engine offers the Tichu call before each of a
  seat's turns until it plays its first card, and once before the pass.
- **Grand Tichu order.** Seats call Grand Tichu one after another, so a
  later seat sees the earlier calls.
