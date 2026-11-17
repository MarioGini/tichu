# Trained models

The app's bots use `assets/bots/tichu_q_v5.safetensors` (loaded by
`lib/agents/app_bots.dart`).

## tichu_q_v4.safetensors (removed)

No longer in the repo; restore it as the benchmark opponent with
`git show 92aed27:assets/bots/tichu_q_v4.safetensors > v4.safetensors`.


Play/pass policy (Q(s, a) MLP, feature schema v4, 252 inputs, same
architecture as v3), trained by `rl/rollout_loop.py`: rollout policy
iteration on exact all-action values, starting from v3 (see `rl/README.md`).

Duplicate duels (`rl/duel.py`), 1000 deal sequences x 2 seatings, to 1000:

| Net | vs classic heuristic | vs v3 | vs previous iteration |
|-----|----------------------|-------|-----------------------|
| v3 (start) | 74.6 % ± 0.9 | — | — |
| iteration 1 (197k labelled decisions) | 81.9 % ± 0.8 | 57.3 % ± 0.9 | 57.3 % ± 0.9 |
| iteration 2 (+121k, a third self-play) | 92.7 % ± 0.6 | 74.3 % ± 0.9 | 67.3 % ± 0.9 |
| iteration 3 (+120k) | 94.2 % ± 0.5 | 79.2 % ± 0.8 | 56.8 % ± 0.9 |

Iteration 3 also wins 90.5 % ± 0.6 against the tuned heuristic
(`HeuristicOptions.latest`). "Classic heuristic" is
`--opponent-heuristic=classic`, the heuristic v3 was trained against. The
file in `assets/bots/` is the newest promoted iteration; later iterations of
the hill climb replace it.

Size and speed: 105,985 float32 parameters (layers 252-256-128-64-1), a
415 KB file. Ranking the legal moves of one decision (6.7 on average) takes
0.33 ms in the app's float64 code path and 0.12 ms with the headless
runner's float32 SIMD path (native code, one 2.1 GHz Xeon core; feature
encoding included, 0.02 ms). A whole match to 1000 between four v4 bots
simulates in 85 ms.

Use with the heuristic's Tichu calls and schupf:

```bash
build/bin/headless --nn-policy=assets/bots/tichu_q_v5.safetensors ...
```

In Dart: `BotConfig(play: LoadedNet.fromBytes(bytes))`.

## tichu_q_v3.safetensors (removed)

No longer in the repo (`git show 92aed27:assets/bots/tichu_q_v3.safetensors`).

The previous policy (behaviour cloning of the heuristic plus Monte-Carlo Q
steps, `rl/train_loop.py`, since removed). Kept as the fixed reference opponent for duels:
74.6 % ± 0.9 vs the classic heuristic on the bench above (70.8 % ± 1.9 in
the original 400-match measurement).

## tichu_call_v1.safetensors (removed)

A Tichu call model (P(go out first | call) from the hand after the schupf);
+0.4 points per decision over the strength rule, not worth a model (see
rl/README.md, "Schupf and calls"). Calls use the heuristic rule.

## tichu_schupf_v2.safetensors (shipped)

Schupf value net (232 inputs, `NnSchupfStrategy`), trained by
`rl/schupf_cf_train.py` on 51,600 exact schupf decisions of v5 self-play (16
candidate passes per decision, each round played out); the second half of
the data was generated with schupf v1 in place. v5 with it beats the previous
bot (v5 + schupf v1) 54.0 % ± 0.7 (2000 deals x 2); v1 had beaten v5 with the
heuristic schupf 55.0 % ± 0.8. Against an opponent's Grand Tichu it passes
the Dog and the lowest cards to the caller and strength to the partner
(`rl/schupf_vs_grand.py`).

## tichu_q_v5.safetensors (shipped)

Two best-response steps against v4 plus one on games against
v4 with the Grand Tichu rule (feature layout v5, history weights zero).
57.3 % ± 0.9 against v4 and 89.7 % ± 0.6 against the heuristic (v4: 88.2 %),
duplicate, 1000 deals x 2, new runner. See rl/README.md, "Review of v4's
games".

