# What we learned (as of 2026-11-24)

These are the measured findings that still guide the work. Every result
comes from a duplicate duel on fresh deals, played as matches to 1000
points (the shipped bot is v8 + schupf v4 + search ≤ 8).

## What moved the bot

| Change | Gain |
|---|---|
| All-action rollout labels instead of one-return DMC (v4) | from ~parity to clearly ahead of the heuristic |
| New inputs: history (v5), claim + received cards (v7 → v8) | v8 vs v7 61 % |
| Schupf nets retrained on the current play | +3–4 pp per retrain |
| Endgame search, 8 worlds, unanimity + margin 10 (≤ 8 cards) | 57 % vs the same bot without search |
| One-on-one solver (≤ 10 cards, also decides the Dragon gift) | +11.5 points per match |
| Graded beatability inputs **with all old data rebuilt** (v10) | 52.4 % vs v8 without search; v10 iterations 1–4 all promoted |
| Belief-weighted worlds, search up to 12 cards | 52.5 % vs the app bot |

The pattern behind these gains: the play net sits at the fixed point of its
training signal. New gains came from new information (inputs or data),
from component nets retrained on the current play, and from search at
decision time.

## What did not

- **A wider net** (512-256-128): no gain. Capacity is not the limit.
- **New inputs trained on one iteration of fresh data**: no gain. The same
  inputs worked once every old cache was rebuilt with them (`data_upgrade.py`).
- **Deep Monte-Carlo labels** (4M one-outcome labels): worse than the
  rollout labels at every evaluation.
- **Stakes-weighted label sampling, out-of-turn bombs for bots, more
  rollout worlds per label**: no gain.
- **Three-player PIMC exact solving, lead rollouts, a pre-schupf Tichu
  rule**: no gain. Removed.
- **A single-opponent promotion gate**: too noisy for steps of about 1 pp.
  The loop now uses a panel gate with a duel cache.

## Findings worth remembering

- **No style collapse from v3 to v8.** Every version beats every earlier
  one in a round robin.
- **Where v8 gained.** Each version is more patient than the one before:
  v8 lets a third of the opponent tricks it could beat go by, keeps its
  bombs for later, and rarely overtakes a partner who called Tichu. The
  whole gain since v3 comes from following plays; leads have not improved
  since v3. The call rule never changed, but its success rate rose with
  the play (Tichu 51 → 63 %).
- **Label noise.** The labels of one round share the deal, so they are
  correlated (+0.4 to +0.5). Hold out whole matches, and spread the labels
  over many deals.
- **Perfect play one-on-one** means the minimax value of the
  perfect-information two-player game. Going out can be worse than passing,
  because a trick containing the Phoenix is worth -25. The v8 net was
  perfect in 90 % of one-on-one decisions where the move matters; the
  solver now plays them exactly
  (up to 10 cards, within its position budget).
- **The Phoenix as last card.** When the Phoenix is played as a player's
  last card and everyone passes, the trick goes to that player, and the
  next player leads. The engine handles this, and
  `phoenix_last_card_test.dart` covers it.
- **The 1000-point rule.** A tie at or above the target is played on
  (`ScoreTracker.gameComplete`).
- **Calls** (exact counterfactual labels): the heuristic rule is worth +1.8
  points for Grand Tichu and +3.8 for Tichu at the first card. The marginal
  Tichu calls lose 13.5 points each, and calling before the schupf is
  negative. Calls remain heuristic. Margin-aware call labels and a joint
  call/schupf plan are still open.

## Current plan

1. Run the v10 rollout loop on all rebuilt data, with the panel gate,
   recording every game (`rl/outputs/v10`).
2. Ship candidate: v10 + schupf j2 (extended candidates) + search ≤ 12 with
   belief worlds + solver. Ship it once it wins ≥ 60 % against the shipped
   bot. With the v10 iteration-3 net it stood at about 57.5 %.
3. Retrain the schupf net and the belief net on v10's play.
4. Before shipping, check the search speed on phones and the web.

## Open

- Human game records are saved to Supabase, but nothing reads them yet.
  The website also needs the repo secrets `SUPABASE_URL` and
  `SUPABASE_ANON_KEY`.
