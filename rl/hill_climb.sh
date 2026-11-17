#!/bin/bash
# Start (or resume) the rollout policy-iteration hill climb in the background.
# Safe to call repeatedly: does nothing while the loop is already running, and
# the loop itself skips every step whose output exists (see rollout_loop.py).
#
#   rl/hill_climb.sh            # start / resume
#   tail -f rl/outputs/rollout_loop/loop.log
cd "$(dirname "$0")/.." || exit 1
if pgrep -f "rl/rollout_loop.py" >/dev/null; then
  echo "hill climb already running"
  exit 0
fi
[ -x build/bin/headless ] || dart compile exe lib/headless/headless.dart -o build/bin/headless
mkdir -p rl/outputs/rollout_loop
# Shard files of a run that was killed (e.g. by a VM restart).
rm -rf /tmp/tichu_shards_* /tmp/tichu_duel_*
# About 30 minutes per iteration on 3 cores: ~70k labelled decisions against
# the heuristics and ~100k from self-play (a quarter of the decisions of
# each game are labelled, so the data covers many different deals).
setsid nohup rl/.venv/bin/python rl/rollout_loop.py \
  --iterations="${ITERATIONS:-30}" \
  --opponents="${OPPONENTS:-classic;latest}" \
  --mixed-episodes="${MIXED:-1200}" --self-episodes="${SELF:-900}" \
  --rollout-rate="${RATE:-0.25}" \
  --window="${WINDOW:-5}" --duel-deals="${DEALS:-1500}" --shards="${SHARDS:-3}" \
  >> rl/outputs/rollout_loop/loop.log 2>&1 &
echo "hill climb started (log: rl/outputs/rollout_loop/loop.log)"
