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

## The bots

The external code lives in `arena/.bots/` and is not committed: it is other
people's code under its own license. `bots.txt` pins the commits.

| bot | what it is | adapter | status |
|---|---|---|---|
| [dave-orr/Tichu-ai](https://github.com/dave-orr/Tichu-ai) | Rust engine of tichu.squidbox.com; rule bots `h2`, search bots `pimcN/h`, `eg:` endgame solver. Its learned nets (`best`) are not public. | `adapters/daveorr` (Rust) | plays |
| [rumoschilling/tichubot](https://github.com/rumoschilling/tichubot) | PPO self-play (36.6 M games), history transformer, released model `tichubot-best.pt` (CC BY-NC) | `adapters/tichubot` (Python, torch) | written, not run yet |
| [Tate-kwon94/tichu](https://github.com/Tate-kwon94/tichu) | AlphaZero-style self-play with a belief model (JS, weights in the repo) | — | todo |
| [ainze/tichu](https://github.com/ainze/tichu) | behaviour cloning from human games plus offline RL, HTTP service | — | todo (model not in the repo) |
| [wemaxon/tichu-agent](https://github.com/wemaxon/tichu-agent) | actor-critic checkpoint | — | todo |
| PavelHolman/tichu, jstanley0/tichu, ohemmali/gichu | rule bots of web Tichu servers | — | todo |

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
