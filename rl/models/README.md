# Trained models

The app's bots use `assets/bots/tichu_q_v4.safetensors` (loaded by
`lib/agents/app_bots.dart`).

## tichu_q_v4.safetensors

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

Use with the heuristic's Tichu calls and schupf:

```bash
build/bin/headless --nn-policy=assets/bots/tichu_q_v4.safetensors ...
```

In Dart: `BotConfig(play: LoadedNet.fromBytes(bytes))`.

## tichu_q_v3.safetensors

The previous policy (behaviour cloning of the heuristic plus Monte-Carlo Q
steps, `rl/train_loop.py`). Kept as the fixed reference opponent for duels:
74.6 % ± 0.9 vs the classic heuristic on the bench above (70.8 % ± 1.9 in
the original 400-match measurement).
