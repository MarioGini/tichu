#!/bin/bash
# Generate exact counterfactual labels for Tichu / Grand Tichu calls in the
# background: the best play policy plays itself, and every call decision is
# labelled with R(call) - R(no call) by forking the round and playing both
# branches (headless --counterfactual-calls). Chunks are written to
# rl/outputs/calls/cf_NNN.jsonl; existing chunks are skipped, so the script
# can be restarted at any time.
#
#   rl/call_labels.sh [chunks]     # default 40 chunks of 120 matches
#   rl/.venv/bin/python rl/call_train.py --jsonl=<merged chunks> --kind=all
cd "$(dirname "$0")/.." || exit 1
if pgrep -f "call_labels_worker" >/dev/null; then
  echo "call labelling already running"
  exit 0
fi
CHUNKS="${1:-40}"
POLICY="${POLICY:-rl/outputs/rollout_loop/best.safetensors}"
mkdir -p rl/outputs/calls
cp "$POLICY" rl/outputs/calls/policy.safetensors
setsid nohup bash -c '
  # call_labels_worker
  for i in $(seq -w 1 '"$CHUNKS"'); do
    out=rl/outputs/calls/cf_$i.jsonl
    [ -f "$out" ] && continue
    build/bin/headless --format=bc-jsonl --target-score=1000 --episodes=120 \
      --seed=$((900000 + 10#$i)) --nn-policy=rl/outputs/calls/policy.safetensors \
      --skip-play-rows --counterfactual-calls --counterfactual-rate=1 \
      --call-epsilon=0.1 --output="$out.tmp" && mv "$out.tmp" "$out"
  done
' >> rl/outputs/calls/labels.log 2>&1 &
echo "call labelling started (rl/outputs/calls)"
