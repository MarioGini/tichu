#!/usr/bin/env python3
"""Rollout policy iteration for the play net (the loop that produced v4 to v6).

Each iteration improves the current best play policy by one exact
policy-improvement step:

  1. Data. The best bot plays (a) against the fixed nets in
     ``--opponent-nets``, the league and the heuristic variants in
     ``--opponents`` (none by default; both seatings) and (b) against
     itself. For a sampled
     share of its play decisions the round is forked once per legal action
     and played out (``headless --rollout-rate``), which gives the exact
     round result of every legal action on that deal.
  2. Train. ``rollout_train.py`` regresses the net on those values as
     per-decision advantages, starting from the best net and using the data
     of *all* iterations so far (more data beat fresher data in every test).
  3. Gate. The candidate must beat the best net in a duplicate duel
     (``duel.py``) by more than ``--promote-z`` standard errors, and again
     on fresh deals (``--confirm-deals``, the two duels pooled), so a lucky
     duel does not promote; it is also measured against the heuristic and
     every fixed net.

League (``--league=K``): every promoted net joins a pool and the K newest
earlier best nets are added to the fixed opponents, so the learner keeps
training against several policies instead of overfitting the last one
(v6 beat v5 60 % but its last iteration only 51.7 % in a row).

Panel gate (``--gate=panel``): one duel against the best net is noisy and
blind to what the candidate does to other opponents (v8 iterations 5 and 6
lost 49.8 % / 51.4 % against iteration 4 but beat every other opponent by
more). The panel gate promotes on the mean, over {best} + fixed nets +
league, of (candidate vs X) - (best vs X) (for X = best: candidate vs best
- 50), each pair on the same deals; best-vs-X results are cached per best
net. No confirmation duel is needed (``--confirm-deals`` is ignored).

Schupf retraining (``--schupf-episodes=N``): after a promotion the new best
plays N self-play matches with exact schupf candidate labels (in chunks of
``--schupf-chunk``, restart-safe), ``schupf_cf_train.py`` fits a new schupf
net on the labels of the last two promotions, and it replaces the learner's
schupf net if it wins a duel (same play net both sides) by ``--promote-z``.
With ``--schupf-label-run`` the labels come from data workers
(``data_worker.py --mode=schupf``, labelling with the published schupf net)
and the retrain runs after every iteration on the newest
``--schupf-label-rows``. ``--schupf-extended``: the learner's schupf net
scores the extended candidate set, in play, duels and labels.

``--upload-run=NAME`` stores every new data file in Supabase Storage
(``training_data_store.py``); a failed upload only warns.

Everything is written to ``--out-dir`` and every step is skipped when its
output already exists, so the loop can simply be restarted after a crash.

  rl/.venv/bin/python rl/rollout_loop.py --out-dir=rl/outputs/v8 --iterations=3 \
      --init-policy=assets/bots/tichu_q_v8.safetensors \
      --opponent-nets=rl/outputs/bench/v6.safetensors --upload-run=v8
"""

from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

from duel import duel as _duel

# Finished duels, by (A, B, deals, seed): a restarted loop (e.g. after a
# 2-hour job limit) does not replay them. Set by main() to out/duel_cache.json.
_DUEL_CACHE: list[Path] = []


def duel(a: list[str], b: list[str], *, deals: int, seed: int, shards: int) -> dict:
    key = json.dumps([a, b, deals, seed])
    path = _DUEL_CACHE[0] if _DUEL_CACHE else None
    cache = json.loads(path.read_text()) if path and path.exists() else {}
    if key in cache:
        return cache[key]
    r = _duel(a, b, deals=deals, seed=seed, shards=shards)
    if path:
        cache = json.loads(path.read_text()) if path.exists() else {}
        cache[key] = r
        path.write_text(json.dumps(cache, indent=1))
    return r
from headless_runner import run_headless_sharded

RL = Path(__file__).resolve().parent
SCHUPF = "assets/bots/tichu_schupf_v4.safetensors"


# The file the latest generate() call wrote (None if it already existed).
last_generated: list[Path | None] = [None]


def generate(out: Path, *, seed: int, episodes: int, shards: int, args: list[str]) -> None:
    """One sharded rollout-labelled run, converted to an npz cache."""
    last_generated[0] = None
    if out.exists():
        return
    jsonl = out.with_suffix(".jsonl")
    t0 = time.time()
    run_headless_sharded(
        base_args=["--format=bc-jsonl", "--record-games", *args],
        seed=seed,
        episodes=episodes,
        output_path=jsonl,
        shards=shards,
    )
    from rollout_train import load, save_npz

    data = load([jsonl])
    tmp = out.with_suffix(".tmp.npz")
    save_npz(data, tmp)
    # The replayable game records (deal + every action of every round) go
    # next to the cache: any future feature can be rebuilt from them.
    import lzma

    games = out.with_suffix(".games.jsonl.xz")
    with jsonl.open("r", encoding="utf-8") as fh, lzma.open(games.with_suffix(".tmp"), "wt") as gz:
        for line in fh:
            if '"game_record"' in line:
                gz.write(line)
    games.with_suffix(".tmp").rename(games)
    tmp.rename(out)
    jsonl.unlink()
    last_generated[0] = out
    print(f"   {out.name}: {data.num_decisions} decisions ({time.time() - t0:.0f}s)", flush=True)


def publish_job(run: str, out: Path, *, it: int, best: Path, schupf: str, opponent_nets: list[str],
                opponent_schupf: str, common_args: list[str]) -> None:
    """Publish what data workers (rl/data_worker.py, other machines) need to
    generate this iteration's data: the nets under fixed names plus
    ``job.json``. Unchanged files are not uploaded again."""
    try:
        from training_data_store import upload_file

        stage = out / "publish"
        stage.mkdir(exist_ok=True)
        files = {"best.safetensors": best}
        if schupf:
            files["schupf.safetensors"] = Path(schupf)
            # Workers in --mode=schupf label with the learner's schupf net.
            files["schupf_label.safetensors"] = Path(schupf)
        if opponent_schupf:
            files["opp_schupf.safetensors"] = Path(opponent_schupf)
        for i, net in enumerate(opponent_nets):
            files[f"opp{i}.safetensors"] = Path(net)
        for name, src in files.items():
            shutil.copy2(src, stage / name)
        job = {
            "iteration": it,
            "opponents": [f"opp{i}.safetensors" for i in range(len(opponent_nets))],
            "schupf": "schupf.safetensors" if schupf else "",
            "opponent_schupf": "opp_schupf.safetensors" if opponent_schupf else "",
            "args": common_args,
        }
        (stage / "job.json").write_text(json.dumps(job, indent=1))
        for name in [*files, "job.json"]:
            upload_file(stage / name, run=run)
    except (OSError, RuntimeError, ValueError, KeyError) as e:  # storage must never stop training
        print(f"   publishing the job failed: {e}", flush=True)


def sync_data(run: str, data_dir: Path) -> None:
    """Fetch data files other machines uploaded to ``run``."""
    try:
        from training_data_store import download

        before = len(list(data_dir.glob("*.npz")))
        download(run, data_dir)
        print(f"   synced {len(list(data_dir.glob('*.npz'))) - before} new files from {run}", flush=True)
    except (OSError, RuntimeError, ValueError, KeyError) as e:  # storage errors
        print(f"   sync from {run} failed: {e}", flush=True)


def _decisions(path: Path) -> int:
    import numpy as np

    with np.load(path) as d:
        return int(d["starts"].size - 1)


def _rows(path: Path) -> int:
    with path.open() as f:
        return sum(1 for _ in f)


def data_window(files: list[Path], max_decisions: int, prune_run: str, count=_decisions) -> list[Path]:
    """The newest files (by iteration, then name) up to ``max_decisions``
    decisions. Older files are dropped from the data directory and, when
    they belong to ``prune_run``, from the store (memory and the 1 GB free
    store bound the data; their game records stay stored)."""
    import re

    def key(f: Path):
        m = re.match(r"it(\d+)_", f.name)
        return (int(m.group(1)) if m else -1, f.name)

    keep, total = [], 0
    for f in sorted(files, key=key, reverse=True):
        if total >= max_decisions:
            break
        keep.append(f)
        total += count(f)
    drop = [f for f in files if f not in keep]
    if drop:
        print(f"   data window: {total} decisions in {len(keep)} files, dropping {len(drop)} older files", flush=True)
        if prune_run:
            try:
                from training_data_store import delete_files, manifest

                names = {f"{prune_run}/{f.name}" for f in drop}
                delete_files([r for r in manifest(prune_run) if r["path"] in names])
            except (OSError, RuntimeError, ValueError, KeyError) as e:  # storage errors
                print(f"   pruning the store failed: {e}", flush=True)
        for f in drop:
            f.unlink()
    return sorted(keep)


def upload(path: Path | None, run: str, policy: Path) -> bool:
    if path is None:  # generated in an earlier (interrupted) run
        return False
    try:
        from training_data_store import upload_file

        upload_file(path, run=run, policy=policy)
        games = path.with_suffix(".games.jsonl.xz")  # replayable game records
        if games.exists():
            upload_file(games, run=run)
        return True
    # Storage must never stop training: network and file errors (OSError),
    # HTTP errors (RuntimeError), unexpected responses (ValueError, KeyError).
    except (OSError, RuntimeError, ValueError, KeyError) as e:
        print(f"   upload of {path.name} failed: {e}", flush=True)
        return False


def _net_key(path: Path) -> str:
    import hashlib

    return hashlib.sha1(Path(path).read_bytes()).hexdigest()[:12]


def panel_gate(args, entry, cand, best, vs_best, opponent_nets, own_schupf, opp_schupf, out: Path) -> bool:
    """Mean gain over the panel {best} + opponent nets, each pair on the same deals."""
    cache_path = out / "best_panel.json"
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    bkey = _net_key(best) + ":" + _net_key(Path(args.schupf_net)) if args.schupf_net else _net_key(best)
    gains = [(vs_best["win_rate"] - 50, vs_best["win_rate_se"])]
    for net in opponent_nets:
        r = duel([f"--nn-policy={cand}", *own_schupf], [f"--opponent-policy={net}", *opp_schupf],
                 deals=args.duel_deals, seed=4242, shards=args.shards)
        entry[f"vs_net[{Path(net).stem}]"] = r
        k = bkey + "|" + _net_key(Path(net))
        if k not in cache:
            cache[k] = duel([f"--nn-policy={best}", *own_schupf], [f"--opponent-policy={net}", *opp_schupf],
                            deals=args.duel_deals, seed=4242, shards=args.shards)
            cache_path.write_text(json.dumps(cache, indent=2))
        b = cache[k]
        gains.append((r["win_rate"] - b["win_rate"], (r["win_rate_se"] ** 2 + b["win_rate_se"] ** 2) ** 0.5))
        print(f"   vs {Path(net).stem}: {r['win_rate']:.1f}% (best {b['win_rate']:.1f}%)", flush=True)
    mean = sum(g for g, _ in gains) / len(gains)
    se = sum(s * s for _, s in gains) ** 0.5 / len(gains)
    entry["panel"] = {"gain": mean, "se": se, "n": len(gains)}
    print(f"   panel gain {mean:+.2f} pp ± {se:.2f} over {len(gains)} opponents", flush=True)
    # A candidate must also not lose to the best net head to head: a panel
    # gain alone can come from exploiting the older nets (v10 iterations
    # 6-8 gained on the panel but lost 48-49 % to their predecessor).
    return mean > args.promote_z * se and vs_best["win_rate"] >= 50


def retrain_schupf(args, it: int, play_net: Path, cur_schupf: Path, data_dir: Path) -> dict | None:
    """Exact schupf labels from the new best's self-play (or the workers'
    labels in ``--schupf-label-run``), new schupf net, keep it if it wins."""
    sdir = data_dir.parent / "schupf"
    sdir.mkdir(exist_ok=True)
    ext = ["--schupf-extended"] if args.schupf_extended else []
    if args.schupf_label_run:
        ldir = sdir / "labels"
        try:
            from training_data_store import download

            download(args.schupf_label_run, ldir)
        except (OSError, RuntimeError, ValueError, KeyError) as e:  # storage errors
            print(f"   schupf label sync failed: {e}", flush=True)
        files = data_window(sorted(ldir.glob("*.jsonl")), 2 * args.schupf_label_rows, args.schupf_label_run,
                            count=_rows)
        # Train on the newest labels only (those of the recent nets); the
        # rest of the window stays for the next retrain.
        train, rows = [], 0
        for f in sorted(files, reverse=True):
            if rows >= args.schupf_label_rows:
                break
            train.append(f)
            rows += _rows(f)
        if rows < args.schupf_label_rows // 2:
            print(f"   schupf retrain skipped: {rows} label rows", flush=True)
            return None
        files = sorted(train)
        print(f"   schupf retrain on {rows} label rows ({len(files)} files)", flush=True)
    else:
        files = _schupf_labels(args, it, play_net, cur_schupf, sdir, ext)
    new = sdir / f"it{it:02d}_schupf.safetensors"
    if not new.exists():
        res = subprocess.run([sys.executable, str(RL / "schupf_cf_train.py"),
                              "--jsonl=" + ",".join(str(x) for x in files), f"--output={new}"],
                             cwd=RL.parent, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(res.stdout + res.stderr)
    r = duel([f"--nn-policy={play_net}", f"--schupf-net={new}", *ext],
             [f"--opponent-policy={play_net}", f"--opponent-schupf-net={cur_schupf}",
              *(["--opponent-schupf-extended"] if ext else [])],
             deals=args.duel_deals, seed=5151 + it, shards=args.shards)
    adopted = r["win_rate"] - 50 > args.promote_z * r["win_rate_se"]
    print(f"   new schupf vs current: {r['win_rate']:.1f}% ± {r['win_rate_se']:.1f} -> "
          f"{'ADOPTED' if adopted else 'kept current'}", flush=True)
    if adopted:
        shutil.copy2(cur_schupf, sdir / f"before_it{it:02d}.safetensors")
        shutil.copy2(new, cur_schupf)
    return {"vs_current": r, "adopted": adopted}


def _schupf_labels(args, it: int, play_net: Path, cur_schupf: Path, sdir: Path, ext: list[str]) -> list[Path]:
    chunks = max(1, args.schupf_episodes // args.schupf_chunk)
    for k in range(chunks):
        f = sdir / f"it{it:02d}_cf{k:02d}.jsonl"
        if f.exists():
            continue
        tmp = f.with_suffix(".tmp")
        run_headless_sharded(
            base_args=["--format=bc-jsonl", "--skip-play-rows", "--schupf-rollout-rate=1",
                       f"--target-score={args.target_score}", "--epsilon=0",
                       f"--nn-policy={play_net}", f"--schupf-net={cur_schupf}", *ext,
                       *(["--schupf-label-extended", "--schupf-candidates=20"] if ext else [])],
            seed=args.seed + 10_000 * it + 7000 + 10 * k,
            episodes=args.schupf_chunk,
            output_path=tmp,
            shards=args.shards,
        )
        tmp.rename(f)
        print(f"   schupf labels {f.name}", flush=True)
    files = sorted(sdir.glob("*_cf*.jsonl"))
    its = sorted({x.name[:4] for x in files})[-2:]
    return [x for x in files if x.name[:4] in its]


def main() -> None:
    p = argparse.ArgumentParser(description="Rollout policy iteration for the play net")
    p.add_argument("--iterations", type=int, default=3)
    p.add_argument("--out-dir", default=str(RL / "outputs" / "rollout_loop"))
    p.add_argument("--init-policy", default="assets/bots/tichu_q_v8.safetensors")
    p.add_argument(
        "--mixed-episodes",
        type=int,
        default=2400,
        help="matches vs the heuristic opponents, the fixed nets and the league per iteration",
    )
    p.add_argument("--self-episodes", type=int, default=1000, help="self-play matches per iteration")
    p.add_argument(
        "--opponents",
        default="",
        help="heuristic specs for the mixed games, separated by ';' (matches are split evenly; "
        "'' = none, 'latest' = the heuristic as written)",
    )
    p.add_argument(
        "--opponent-nets",
        default="",
        help="fixed play nets to train and measure against, separated by ';' "
        "(share --mixed-episodes with the heuristic opponents)",
    )
    p.add_argument(
        "--schupf-net",
        default=SCHUPF,
        help="schupf net of the learner in every game and duel ('' = heuristic schupf); "
        "the play net is trained for the exchange it actually plays with",
    )
    p.add_argument(
        "--opponent-schupf-net",
        default=SCHUPF,
        help="schupf net of the --opponent-nets team ('' = heuristic schupf)",
    )
    p.add_argument(
        "--train-args",
        default="",
        help="extra rollout_train.py arguments (its defaults: EMA 0.999, recency 0.8; "
        "the epoch with the best held-out gain is kept)",
    )
    p.add_argument("--rollout-rate", type=float, default=0.5)
    p.add_argument(
        "--gen-args",
        default="",
        help="extra headless arguments for every data run, e.g. '--rollout-max-actions=16'",
    )
    p.add_argument("--epsilon", type=float, default=0.02)
    p.add_argument("--target-score", type=int, default=1000)
    p.add_argument("--epochs", type=int, default=4)
    p.add_argument("--lr", type=float, default=3e-4)
    p.add_argument("--window", type=int, default=0, help="train on the last N iterations (0 = all)")
    p.add_argument("--duel-deals", type=int, default=1000)
    p.add_argument("--promote-z", type=float, default=2.0)
    p.add_argument("--gate", choices=["best", "panel"], default="best")
    p.add_argument("--schupf-episodes", type=int, default=0, help="schupf retrain after a promotion (0 = off)")
    p.add_argument("--schupf-chunk", type=int, default=250)
    p.add_argument("--schupf-extended", action="store_true",
                   help="the learner's schupf net scores the extended candidate set (labels too)")
    p.add_argument("--schupf-label-run", default="",
                   help="store run with worker schupf labels (data_worker.py --mode=schupf): the schupf "
                        "net is retrained from them after every iteration instead of after promotions")
    p.add_argument("--schupf-label-rows", type=int, default=400_000,
                   help="newest schupf label rows per retrain (twice as many are kept)")
    p.add_argument(
        "--confirm-deals",
        type=int,
        default=1000,
        help="second duel on fresh deals before a promotion (0 = off); both duels pooled",
    )
    p.add_argument(
        "--league",
        type=int,
        default=2,
        help="also train and measure against the K newest earlier best nets (0 = off)",
    )
    p.add_argument("--upload-run", default="", help="upload new data files to Supabase under this run name")
    p.add_argument(
        "--publish-run",
        default="",
        help="publish the nets + job.json for rl/data_worker.py under this store run every iteration",
    )
    p.add_argument(
        "--sync-run",
        default="",
        help="before training, download the data files of this store run (the workers' data)",
    )
    p.add_argument(
        "--max-decisions",
        type=int,
        default=0,
        help="train on the newest files up to this many decisions; older ones are deleted "
        "locally and from --upload-run (0 = keep everything)",
    )
    p.add_argument("--shards", type=int, default=4)
    p.add_argument("--seed", type=int, default=100_000)
    args = p.parse_args()

    out = Path(args.out_dir)
    _DUEL_CACHE.append(out / "duel_cache.json")
    data_dir, nets = out / "data", out / "nets"
    data_dir.mkdir(parents=True, exist_ok=True)
    nets.mkdir(parents=True, exist_ok=True)
    best = out / "best.safetensors"
    if not best.exists():
        shutil.copy2(args.init_policy, best)
    history_path = out / "history.json"
    history = json.loads(history_path.read_text()) if history_path.exists() else []
    start = 1 + max((h["iter"] for h in history), default=0)
    opponents = [o for o in args.opponents.split(";") if o]
    fixed_nets = [o for o in args.opponent_nets.split(";") if o]
    pool_dir = out / "pool"
    pool_dir.mkdir(exist_ok=True)
    # The learner's schupf net may be replaced by the retrain step.
    cur_schupf = out / "schupf.safetensors"
    if args.schupf_net and not cur_schupf.exists():
        shutil.copy2(args.schupf_net, cur_schupf)
    if args.schupf_net:
        args.schupf_net = str(cur_schupf)
    own_schupf = [f"--schupf-net={args.schupf_net}"] if args.schupf_net else []
    if args.schupf_net and args.schupf_extended:
        own_schupf.append("--schupf-extended")
    opp_schupf = [f"--opponent-schupf-net={args.opponent_schupf_net}"] if args.opponent_schupf_net else []
    # The candidate and the best net play the duel with the same schupf.
    best_schupf = [f"--opponent-schupf-net={args.schupf_net}"] if args.schupf_net else []
    if args.schupf_net and args.schupf_extended:
        best_schupf.append("--opponent-schupf-extended")

    for it in range(start, start + args.iterations):
        t0 = time.time()
        print(f"\n=== iteration {it} ===\n1) rollout data from {best}", flush=True)
        pool = sorted(pool_dir.glob("it*.safetensors"))[-args.league:] if args.league > 0 else []
        opponent_nets = fixed_nets + [str(x) for x in pool]
        if pool:
            print("   league: " + ", ".join(x.stem for x in pool), flush=True)
        common = [
            f"--target-score={args.target_score}",
            f"--rollout-rate={args.rollout_rate}",
            f"--epsilon={args.epsilon}",
            f"--nn-policy={best}",
            *own_schupf,
            *shlex.split(args.gen_args),
        ]
        if args.publish_run:
            publish_job(
                args.publish_run,
                out,
                it=it,
                best=best,
                schupf=args.schupf_net,
                opponent_nets=opponent_nets,
                opponent_schupf=args.opponent_schupf_net,
                common_args=[a for a in common if not a.startswith(("--nn-policy=", "--schupf-net="))],
            )
        seed = args.seed + 10_000 * it
        per = max(1, args.mixed_episodes // (2 * max(1, len(opponents) + len(opponent_nets))))
        for i, net in enumerate(opponent_nets):
            for swap in (False, True):
                generate(
                    data_dir / f"it{it:02d}_net{i}{'b' if swap else 'a'}.npz",
                    seed=seed + 2000 + 100 * i + int(swap),
                    episodes=per,
                    shards=args.shards,
                    args=common
                    + ["--mixed", f"--opponent-policy={net}", *opp_schupf]
                    + (["--swap-teams"] if swap else []),
                )
                if args.upload_run:
                    upload(last_generated[0], args.upload_run, best)
        for i, spec in enumerate(opponents):
            for swap in (False, True):
                generate(
                    data_dir / f"it{it:02d}_mix{i}{'b' if swap else 'a'}.npz",
                    seed=seed + 100 * i + int(swap),
                    episodes=per,
                    shards=args.shards,
                    args=common
                    + ["--mixed", f"--opponent-heuristic={spec}"]
                    + (["--swap-teams"] if swap else []),
                )
                if args.upload_run:
                    upload(last_generated[0], args.upload_run, best)
        if args.self_episodes > 0:
            generate(
                data_dir / f"it{it:02d}_self.npz",
                seed=seed + 5000,
                episodes=args.self_episodes,
                shards=args.shards,
                args=common,
            )
            if args.upload_run:
                upload(last_generated[0], args.upload_run, best)

        print("2) train", flush=True)
        if args.sync_run:
            sync_data(args.sync_run, data_dir)
        files = sorted(data_dir.glob("*.npz"))
        if args.max_decisions > 0:
            files = data_window(files, args.max_decisions, args.upload_run)
        if args.window > 0:
            keep = {f"it{k:02d}" for k in range(it - args.window + 1, it + 1)}
            files = [f for f in files if f.name[:4] in keep]
        cand = nets / f"it{it:02d}.safetensors"
        res = None if cand.exists() else subprocess.run(
            [
                sys.executable,
                str(RL / "rollout_train.py"),
                "--jsonl=" + ",".join(str(f) for f in files),
                f"--init-from={best}",
                f"--output={cand}",
                f"--epochs={args.epochs}",
                f"--lr={args.lr}",
                "--allow-worse",
                *shlex.split(args.train_args),
            ],
            cwd=RL.parent,
            capture_output=True,
            text=True,
        )
        if res is None:
            print(f"   {cand.name} already trained", flush=True)
        elif res.returncode != 0:
            cand.unlink(missing_ok=True)
            raise RuntimeError(res.stdout + res.stderr)
        else:
            print("   " + res.stdout.strip().splitlines()[-1], flush=True)

        print("3) duels", flush=True)
        vs_best = duel(
            [f"--nn-policy={cand}", *own_schupf],
            [f"--opponent-policy={best}", *best_schupf],
            deals=args.duel_deals,
            seed=4242 + it,
            shards=args.shards,
        )
        promoted = vs_best["win_rate"] - 50 > args.promote_z * vs_best["win_rate_se"]
        print(f"   vs best: {vs_best['win_rate']:.1f}% ± {vs_best['win_rate_se']:.1f}", flush=True)
        entry = {"iter": it, "vs_best": vs_best, "data_files": len(files)}
        if args.gate == "panel":
            promoted = panel_gate(args, entry, cand, best, vs_best, opponent_nets, own_schupf, opp_schupf, out)
        elif promoted and args.confirm_deals > 0:
            confirm = duel(
                [f"--nn-policy={cand}", *own_schupf],
                [f"--opponent-policy={best}", *best_schupf],
                deals=args.confirm_deals,
                seed=777_000 + 1000 * it,
                shards=args.shards,
            )
            entry["vs_best_confirm"] = confirm
            n1, n2 = args.duel_deals, args.confirm_deals
            pooled = (vs_best["win_rate"] * n1 + confirm["win_rate"] * n2) / (n1 + n2)
            pooled_se = (
                (vs_best["win_rate_se"] * n1) ** 2 + (confirm["win_rate_se"] * n2) ** 2
            ) ** 0.5 / (n1 + n2)
            promoted = confirm["win_rate"] > 50 and pooled - 50 > args.promote_z * pooled_se
            print(
                f"   confirm (fresh deals): {confirm['win_rate']:.1f}% ± {confirm['win_rate_se']:.1f}, "
                f"pooled {pooled:.1f}% ± {pooled_se:.1f}",
                flush=True,
            )
        entry["promoted"] = promoted
        print(f"   -> {'PROMOTED' if promoted else 'rejected'}", flush=True)
        for spec in opponents:
            r = duel(
                [f"--nn-policy={cand}", *own_schupf],
                [f"--opponent-heuristic={spec}"],
                deals=args.duel_deals,
                seed=4242,
                shards=args.shards,
            )
            entry[f"vs_heuristic[{spec}]"] = r
            print(
                f"   vs heuristic [{spec}]: {r['win_rate']:.1f}% ± {r['win_rate_se']:.1f} "
                f"margin {r['margin']:+.0f}",
                flush=True,
            )
        for net in opponent_nets if args.gate != "panel" else []:
            r = duel(
                [f"--nn-policy={cand}", *own_schupf],
                [f"--opponent-policy={net}", *opp_schupf],
                deals=args.duel_deals,
                seed=4242,
                shards=args.shards,
            )
            entry[f"vs_net[{Path(net).stem}]"] = r
            print(
                f"   vs {Path(net).stem}: {r['win_rate']:.1f}% ± {r['win_rate_se']:.1f} "
                f"margin {r['margin']:+.0f}",
                flush=True,
            )
        if args.schupf_net and (args.schupf_label_run or (promoted and args.schupf_episodes > 0)):
            entry["schupf"] = retrain_schupf(args, it, cand if promoted else best, cur_schupf, data_dir)
        if promoted:
            if args.league > 0:
                # The net being replaced joins the league pool.
                shutil.copy2(best, pool_dir / f"it{it:02d}.safetensors")
            shutil.copy2(cand, best)
        entry["seconds"] = time.time() - t0
        history.append(entry)
        history_path.write_text(json.dumps(history, indent=2))

    print(f"\nbest policy: {best}")


if __name__ == "__main__":
    main()
