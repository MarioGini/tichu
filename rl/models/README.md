# Trained models

The app (`lib/agents/app_bots.dart`) loads:

| Asset | What | Inputs |
|---|---|---|
| `assets/bots/tichu_q_v8.safetensors` | play net v8, iteration 5 of the v8 league run | 376 (schema v7), 376-256-128-64-1 |
| `assets/bots/tichu_schupf_v4.safetensors` | schupf net, `schupf_cf_train.py` on 62,540 exact decisions of v8 self-play | 232 |

The app also runs endgame search (≤ 8 cards) and the one-on-one solver
(budget 10,000). Calls, the wish and Dragon gifts outside the solver are
heuristic.

Results against the previous shipped bot (v7 + schupf v3), duplicate duels
on fresh deals:

| Bot | Search | Result |
|---|---|---|
| v8 + schupf v4 | both sides, as in the app | **61.3 % ± 1.0**, +164 per match (1000 deals x 2) |
| v8 + schupf v4 | none | 63.6 % ± 0.9 |

All training data and earlier nets are in Supabase Storage
(`rl/training_data_store.py list`, `download --run=<run>`). Removed nets
remain available in git history.
