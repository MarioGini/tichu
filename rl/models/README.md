# Trained models

The app (`lib/agents/app_bots.dart`) loads:

| Asset | What | Inputs |
|---|---|---|
| `assets/bots/tichu_q_v10.safetensors` | play net v10, iteration 10 of the v10 rollout loop (panel gate, data workers) | 431 (schema v9), 431-256-128-64-1 |
| `assets/bots/tichu_schupf_v5.safetensors` | schupf net (j2), `schupf_cf_train.py` on exact labels with the extended candidate set | 232 |
| `assets/bots/tichu_belief_v1.safetensors` | card-location (belief) net, `belief_train.py`: who holds each unseen card | 373 state inputs, 373-512-256-168 |

The app also runs endgame search up to 12 cards in hand, with worlds
re-dealt by the belief net, and the one-on-one solver (budget 20,000).
Calls, the wish and Dragon gifts outside the solver are heuristic.

Results against the previous shipped bot (v8 + schupf v4 + search ≤ 8 +
solver), duplicate duels on fresh deals, matches to 1000:

| Bot | Search | Result |
|---|---|---|
| v10 + schupf v5 | both sides, as in the app | **63.7 % ± 1.4**, +176 per match (480 deals x 2) |
| v10 net only | none, both sides | 60–62 % (600 deals x 2, loop gate) |

Only nets of the current feature layout run, so `assets/bots/` holds just
the shipped nets; duels and the training loop use them as the baseline.
All training data and earlier nets are in Supabase Storage
(`rl/training_data_store.py list`, `download --run=<run>`). Removed nets
remain available in git history.
