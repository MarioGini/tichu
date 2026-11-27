# Tichu bots out there (November 2026)

What other Tichu AIs exist, how they work, how strong they are, and how
ours compares. Matches are played over the bot bridge (`doc/bot_bridge.md`,
`arena/`). Our bot is the shipped app bot: play net v10, schupf v5, endgame
search up to 12 cards with belief worlds, and the one-on-one solver.

## Results so far

Duplicate matches: each of 200 deals is played twice with the teams
swapped, in full games to 1000. ± is one standard error.

| opponent | our win rate | margin a game |
|---|---|---|
| dave-orr `eg:pimc10/h` (search over h2 rollouts, exact endgames) | **98.5 % ± 0.6** | +973 ± 17 |
| dave-orr `h2` (rule bot) | **93.8 % ± 1.3** | +739 ± 21 |
| rumoschilling `tichubot` (PPO self-play, 36.6 M games) | **67.8 % ± 2.3** | +306 ± 28 |
| tichuengine.com Grandmaster (Sean McCarthy; our bot in one seat with a Grandmaster partner, so 50 % = equal; 15 games, 143 hands, not duplicate) | **1 of 15** | −502 ± 97 (−53 a hand) |

How to read these:

- **pimc10/h against h2.** In dave-orr's own arena, `pimc10/h` loses to
  `h2` at the current commit (−19.6 ± 15.5 a deal, 200 deals). The search
  bot is weaker than his newer rule bot, so the order above is
  consistent.
- **Our level against dave-orr's best.** His `best` (net plus search, not
  public) beats `h2` 93.8 % ± 2.0, +756 ± 37. We beat `h2` by the same
  margin, so through `h2` we are about level with `best`.
- **tichubot** is the strongest opponent we have played. It never
  searches; it samples its moves from the policy.

## The bots, strongest first

### 1. Sean McCarthy, tichuengine.com (closed)

- **How it works**: Gumbel AlphaZero. Three nets from self-play only, over
  9 M games:
  - a belief net (where the unseen cards are);
  - a policy net, trained on search games;
  - a value net that sees all four hands, trained on plain policy games.

  At play time it samples about 20 worlds and runs a shallow tree search
  with sequential halving, with the value net at the leaves and no
  play-outs. It has separate nets for the mode with out-of-turn bombs.
- **Strength**: beats ainze's served champion by **+43.9 ± 5.7 a round**.
  Its policy alone, without search, still wins by +13.4.
- **Source**: ainze's notes,
  `docs/notes/2026-11-14-sean-bot-gap-value-search-and-policy-finetune.md`.
  This is the bot to beat.
- **Access**: none. There is no code, and the website is not reachable
  from our sandbox.

#### His schupf, reverse-engineered

From 861 passes of his Grandmaster bots: 477 at our tables, and 384 from
all-bot reference games of the duplicate sets we played. The hand
histories show each seat's 14 cards and the 3 it passed.

- **Opponents get low cards only.** Mostly 2s and 3s, nothing above a
  Jack. The Mah Jong, Phoenix and Dragon never go to an opponent, the Dog
  7 times in 861 passes (ours: 25 times in 159).
- **A parity convention for the opponents.** With "odd left", seat+1 gets
  an odd rank (59 %) and seat+3 an even one (88 %); "even left" is the
  mirror. Within the parity it is the lowest card 58 % of the time, so
  hand shape also counts.
- **The partner card is a signal.** Under the "2+HC odd" convention, HC
  is Aces, Dragon and Phoenix.
  - With 2 or more HC, the partner gets an **odd** card (160 odd,
    16 even).
  - With fewer, it gets an **even** card, usually the passer's highest
    even card (106 of 140).
  - A hand with a single HC often gives that card itself: Phoenix 40,
    Dragon 12.

  The partner learns how strong the passer is, for calls and for who
  takes control. Our bot sends no such signal, and our play net was never
  trained to read one.
- **Conventions are table settings** ("free choice", "2+HC odd/even/low",
  "give 1 HC", "ternary"). His bots play to whichever is declared, so they
  are trained with the convention as an input.

### 2. ainze/tichu (code public, weights not)

- **How it works**:
  - behaviour cloning on about 100 k human games from BSW (Brettspielwelt),
    weighted by the players' TrueSkill;
  - then offline RL (AWR) and on-policy co-training;
  - a residual MLP policy, learned Grand and Tichu call nets, an HTTP
    inference service.
- **Engineering**: very careful work, with 45+ ADRs and preregistered
  experiments.
- **Finding that matters for us**: on top of a finished policy, one-step
  search and fine-tuning on play-out results gain almost nothing (+1 to +7
  a round). Sean's gain comes from the loop, not from polish.
- **Recent activity**: engine rule fixes in November:
  - a one-suit straight is a bomb only;
  - a round ending on a Mah Jong play is scored;
  - an out-of-turn bomb of the wished rank clears the wish.

### 3. dave-orr/Tichu-ai (code public, best nets not)

- **What it is**: a Rust port of the tichu.squidbox.com engine plus a bot
  harness. The duplicate arena, the replay viewer and the live play on
  squidbox are all public.
- **The bots**:
  - `h2`: rules with card tracking, hand structure, lead planning and
    defence;
  - `pimcN/h`: N guessed deals with h2 rollouts per candidate play;
  - `eg:`: exact alpha-beta for two-player endgames;
  - `net:` / `search:` / `best`: a learned net from Deep Monte Carlo
    self-play (DouZero-style), plus search at every play (24 guessed deals
    over the net's top 3 moves), plus learned Tichu and Grand calls.
- **Activity**: the most active of all, with 27 commits in the last week.
  The squidbox server now seats bots at human tables. Its bot API needs
  the server owner's token.

### 4. rumoschilling/tichubot (model public, CC BY-NC)

- **How it works**: PPO self-play with Magnetic Mirror Descent instead of
  an entropy schedule, over 36.6 M games (a week on one RTX 3080).
  - An MLP over the situation plus a small transformer over the round's
    plays.
  - Separate small nets for passing, Grand calls, the Dragon gift and the
    wish.
- **Strength**: measured only against its own checkpoints, still improving
  at 36.6 M. Against us: 32 % of games.

### 5. Tate-kwon94/tichu (weights in the repo)

- **How it works**: AlphaZero-style PUCT search (950 ms a move) over a
  self-play net, a linear belief model, and heads for declaring, the
  exchange and endgames. Plain JS, no dependencies.
- **Strength**: by its own notes, RL bought about +2.8 a round over its
  heuristic, and its promotion gates mostly failed.
- **Activity**: inactive since September.
- **Status here**: not played yet; no adapter.

### The rest

Small RL experiments and rule bots, none with measured strength:
wemaxon/tichu-agent (actor-critic), freeCode4e (C# linear self-play),
PavelHolman/tichu, jstanley0/tichu, ohemmali/gichu (web servers with rule
bots), lukaspestalozzi (2017 DQN), and the Bern 2024 thesis (PPO+BC,
"amateur level"). The commercial apps (House Full of Games, Tichu One,
Steam) have closed rule bots that reviewers call weak.

## What it takes to be the best

- **Where we are.** We beat everything public that we can run. By the
  `h2` yardstick we match dave-orr's best.
- **The gap.** Sean's bot is the strongest known, and his recipe says
  where the remaining strength is: search with a belief net and a value
  net in the training loop, the policy trained on search targets over
  millions of games.
- **What we have.** Ours already has a belief net and endgame search
  (≤ 12 cards). Search over the whole round, fed back into training, is
  the next step.

## Engine bugs found by playing other engines (all fixed)

1. The Phoenix could pair the Mah Jong, in full houses (K-K-K + Mah Jong +
   Phoenix) and in pair straights (1-1-2-2).
2. Straights were deduplicated by top card only, and the Phoenix never
   extended a straight downwards. Our bots could not play PH-3-4-5-6 while
   keeping the seven.
3. A one-suit straight was also offered as a plain straight, which a
   higher straight can beat.
4. Our bot called Tichu after an opponent was out, which can only lose
   100. This was a bot bug, not an engine bug.

## Rule differences kept on purpose

- **A bomb instead of the wish.** In dave-orr's engine, any bomb may be
  played when you could fulfil the wish. Ours, ainze's and tichubot's
  require the wished rank; a bomb only counts when it contains it.
- **Out-of-turn bombs.** Our bots bomb on their own turn only. People in
  the app can bomb at any time. ainze measured out-of-turn bombs at about
  2 % of human rounds.
- **Shorter bombs inside a straight flush.** From 8-K in one suit, 8-Q
  and 9-K are legal bombs too. A person may play them, and the bridge
  offers them to other bots. Our bots consider only the whole run
  (`getBombs`): it beats the shorter ones and sheds more cards, so
  splitting is practically never better.
- **Tichu after someone is out.** Our engine allows the call, as the rules
  do: it may be called until your first card. It always fails. Dave-orr's
  engine refuses it.
