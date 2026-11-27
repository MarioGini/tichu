# Arena results

Our side: the shipped app bot (`arena/shipped.args`). Duplicate: every deal
is played twice with the teams swapped. Full games to 1000. ± is one
standard error over the deal pairs.

| date | opponent | deals x 2 | our win rate | margin a game | notes |
|---|---|---|---|---|---|
| 2026-11-26 | dave-orr `h2` (rule bot) | 200 | **93.8 % ± 1.3** | +739 ± 21 | our engine before the straight and bomb fixes; for scale: dave-orr's own `best` (net + search) beats `h2` 93.8 % ± 2.0, +756 ± 37 (their README, 273 game pairs) |
| 2026-11-27 | dave-orr `h2`, rerun on the fixed engine (PR #45) | 200 | **93.8 % ± 1.3** | +737 ± 21 | same deals as above: the fixes cost nothing |
| 2026-11-26 | dave-orr `eg:pimc10/h` (search over h2 rollouts) | 200 | **98.5 % ± 0.6** | +973 ± 17 | in their own arena pimc10/h loses to h2 (−19.6 ± 15.5 a deal) |
| 2026-11-26 | rumoschilling `tichubot` 36.6 M (PPO self-play, samples its moves) | 200 | **67.8 % ± 2.3** | +306 ± 28 | our engine with the straight and bomb fixes |
