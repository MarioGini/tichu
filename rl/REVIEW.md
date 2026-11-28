# What we learned (as of 2026-11-26)

These are the measured findings that still guide the work. Every result
comes from a duplicate duel on fresh deals, played as matches to 1000
points (the shipped bot is v10 + schupf v5 + belief search ≤ 12 + solver).

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
| More data from worker sessions (~6.5M-decision window) + gate needing ≥ 50 % vs the best | v10 iterations 9–10 promoted again after a plateau; it10 vs v8 60–62 % without search |
| Shipped v10 + schupf v5 + belief search ≤ 12 + solver | **63.7 % ± 1.4** vs v8 + schupf v4 + search ≤ 8 + solver |
| Sequential halving with the net's prior instead of the 8 × 7 grid (same 56 rollouts, `minZ` 1), same nets | **56.0 % ± 1.1**, +86 per match (2 × 300 deals x 2) vs the grid; halving alone 54.4 % |

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
- **A panel gate alone**: v10 iterations 6–8 gained on the panel but lost
  48–49 % to their predecessor (they exploited older nets). The gate now
  also needs ≥ 50 % against the best.
- **Schupf retrained on v10 play** (400k worker labels): 51.0 and 50.9 %
  vs j2, not adopted. The schupf net is not the bottleneck right now.

## Findings worth remembering

- **No style collapse from v3 to v8.** Every version beats every earlier
  one in a round robin.
- **Where v10 gained.** Judged one move at a time on v8's positions (v8
  playing the rest), v10 is no better than v8 (+0.07 ± 0.77). Its edge is
  coherent play over several moves: more first-outs (48.9 → 50.6 %), fewer
  double losses (13.8 → 11.5 %), and higher call success at the same call
  rate (Tichu 63.5 → 65.9 %, Grand 63.3 → 66.1 %). Leads are the first
  hint of a gain since v3 (+1.6 ± 1.8, not significant).
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

1. Keep the v10 loop running with data workers; the loop retrains the
   schupf net from worker labels after every iteration.
2. Retrain the belief net on v10's play.
3. Learned or re-tuned calls: call success rose at an unchanged call rate,
   so the heuristic thresholds may now be too cautious.

## Open

- Human game records are saved to Supabase, but nothing reads them yet.
  The website also needs the repo secrets `SUPABASE_URL` and
  `SUPABASE_ANON_KEY`.
