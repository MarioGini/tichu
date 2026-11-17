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
setsid nohup rl/.venv/bin/python rl/rollout_loop.py \
  --iterations="${ITERATIONS:-30}" \
  --opponents="${OPPONENTS:-classic;latest}" \
  --mixed-episodes="${MIXED:-600}" --self-episodes="${SELF:-250}" \
  --window="${WINDOW:-5}" --duel-deals="${DEALS:-800}" --shards="${SHARDS:-3}" \
  >> rl/outputs/rollout_loop/loop.log 2>&1 &
echo "hill climb started (log: rl/outputs/rollout_loop/loop.log)"
