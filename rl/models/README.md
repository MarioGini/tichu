# Trained models

## tichu_q_v3.safetensors

Play/pass policy (Q(s, a) MLP, feature schema v4, 252 inputs) trained by
`rl/train_loop.py` (v3): behaviour cloning of the improved heuristic, then
Monte-Carlo Q steps (DouZero-style, PerfectDou-style oracle baseline).

- 70.8 % ± 1.9 match win rate (to 1000, duplicate, 400 matches, fresh
  deals) vs the heuristic bot, average margin +280.
- Use with the heuristic's Tichu calls and schupf (learned call / schupf
  nets measured worse):

```bash
build/bin/headless --nn-policy=rl/models/tichu_q_v3.safetensors ...
```

In Dart: `BotConfig(play: LoadedNet.fromBytes(bytes))`.
