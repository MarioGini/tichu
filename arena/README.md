# Arena: our bots against other people's Tichu bots

Other Tichu bots play the opponent team in our headless runner over the
bot bridge (`doc/bot_bridge.md`). Our engine stays the rules authority.
Each adapter translates the bridge's requests into its bot's own engine.

```
arena/fetch.sh                                   # clone the bots at pinned commits
(cd arena/adapters/daveorr && cargo build --release)
python3 rl/duel.py --a="$(cat arena/shipped.args)" \
  --b="--opponent-external='arena/adapters/daveorr/target/release/daveorr_bridge h2'" \
  --deals=200 --shards=4
```

`shipped.args` is the app bot: play net v10, schupf v5 (extended), endgame
search up to 12 cards with belief worlds, and the one-on-one solver. Every
deal is played twice with the teams swapped (duplicate), so both sides get
the same cards.

## The bots, strongest first (judged from their code and their own measurements)

The external code lives in `arena/.bots/` and is not committed: it is other
people's code under its own license. `bots.txt` pins the commits.

| # | bot | method | evidence of strength | can we play it? |
|---|---|---|---|---|
| 1 | **Sean McCarthy, tichuengine.com** (closed) | Gumbel AlphaZero: belief, policy and value nets, ~20 sampled worlds, shallow search; >9 M self-play games; the policy is trained on search games, the value net on policy games | beats ainze's served champion by **+43.9 ± 5.7 a round**; its policy without search, by +13.4 (ainze, `docs/notes/2026-11-14-sean-bot-gap...`) | no code; website only (not reachable from here) |
| 2 | **ainze/tichu** | behaviour cloning on ~100 k BSW human games, then offline RL (AWR) and co-training; residual MLP; HTTP inference service | a gated champion line; loses to #1 by 44 a round | code yes, **weights not published** |
| 3 | **dave-orr/Tichu-ai `best`** | learned net (DMC self-play) plus search at every play (24 guessed deals over the net's top 3, exact 1-on-1 endgames), learned calls | `best` beats `h2` in 93.8 % of games, its own net without search in 66 %; plays live on tichu.squidbox.com | code yes, nets not published. **Public: `h2`, `pimcN/h` (search over h2 rollouts), `eg:` (exact endgames)** |
| 4 | **rumoschilling/tichubot** | PPO self-play with Magnetic Mirror Descent, 36.6 M games, MLP plus history transformer; separate pass, Grand, Dragon and wish heads; samples its moves, no search | still improving at 36.6 M (+26 a deal over the 18.8 M best); measured only against itself | yes: `tichubot-best.pt` release (CC BY-NC), `adapters/tichubot` |
| 5 | **Tate-kwon94/tichu** | AlphaZero-style PUCT (950 ms a move) over a self-play net plus a belief model, JS | its own notes: RL gained ~+2.8 a round over its heuristic, promotion gates mostly failed | yes: weights in the repo (JSON); no adapter yet |
| – | wemaxon, freeCode4e, PavelHolman, jstanley0, gichu, lukaspestalozzi, ... | small RL agents or rule bots | none | not worth the time first |

Focus: #3's public search bots now, #4 next (needs the OK to run its
checkpoint), #5 after. #1 and #2 can only be met through their authors.

What #1 tells us about getting stronger: ainze found that one-step search
or fine-tuning on top of a finished policy gains almost nothing (+1 to +7).
The gain is in the loop: search with a belief net and a value net, and the
policy trained on the search's targets over millions of games.

## What the adapters have to bridge

- **Hidden hands.** An adapter rebuilds the round in its bot's engine.
  The other seats' hands are guessed so that they explain every play,
  every pass under a Mah Jong wish, and who led first (the Mah Jong).
- **Rules where the engines differ.** Our engine is the referee. When a
  real move is illegal in the other engine, the adapter takes it as a fact
  instead of failing. Cases so far:
  - Tichu called after someone is out. That was our bot's mistake, now
    fixed.
  - Moves under a wish that no guessed hand explains. These are logged to
    `$BRIDGE_WISH_LOG`.
- **Missing options.** Our move generator lists one straight per length
  and top rank. When their bot picks an unlisted suit or Phoenix variant,
  the adapter plays the listed one of the same type, length and rank.
- **Bombs out of turn.** Not modelled (`doc/bot_bridge.md`). Their bots
  bomb on their own turn.

Found on the way, and fixed: our engine accepted the Phoenix as a pair
with the Mah Jong, in full houses and pair straights.
