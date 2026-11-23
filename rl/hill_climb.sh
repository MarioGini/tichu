#!/bin/bash
# Start (or resume) the rollout policy-iteration hill climb in the background.
# Safe to call repeatedly: does nothing while the loop is already running, and
# the loop itself skips every step whose output exists (see rollout_loop.py).
#
#   rl/hill_climb.sh            # start / resume
#   tail -f rl/outputs/rollout_loop/loop.log
cd "$(dirname "$0")/.." || exit 1
# Also resume the call-label generation when it was started before
# (rl/call_labels.sh, uses the remaining core).
[ -d rl/outputs/calls ] && rl/call_labels.sh "${CALL_CHUNKS:-40}"
if pgrep -f "rl/rollout_loop.py" >/dev/null; then
  echo "hill climb already running"
  exit 0
fi
[ -x build/bin/headless ] || dart compile exe lib/headless/headless.dart -o build/bin/headless
mkdir -p rl/outputs/rollout_loop
# Shard files of a run that was killed (e.g. by a VM restart).
rm -rf /tmp/tichu_shards_* /tmp/tichu_duel_*
# The loop's defaults are the settings of the v7/v8 runs (league of 2, 2400
# league matches + 1000 self-play matches per iteration, rollout rate 0.5);
# about 50 minutes per iteration on 4 cores. Extra loop arguments, e.g. a
# fixed opponent net: LOOP_ARGS="--opponent-nets=rl/outputs/bench/v6.safetensors".
# shellcheck disable=SC2086
setsid nohup rl/.venv/bin/python rl/rollout_loop.py \
  --iterations="${ITERATIONS:-30}" --shards="${SHARDS:-4}" ${LOOP_ARGS:-} \
  >> rl/outputs/rollout_loop/loop.log 2>&1 &
echo "hill climb started (log: rl/outputs/rollout_loop/loop.log)"
