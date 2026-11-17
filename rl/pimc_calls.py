#!/usr/bin/env python3
"""Score decision-time simulation (PIMC) for Tichu calls on exact labels.

Rows from ``headless --counterfactual-calls --pimc-worlds=N``: ``cf`` is the
exact call value on the real deal, ``pimc_cf`` the average call value over
N guessed deals of the unseen cards (what the player could compute).

  rl/.venv/bin/python rl/pimc_calls.py rl/outputs/pimc/cf.jsonl
"""

import json
import sys

import numpy as np

rows = [json.loads(l) for l in open(sys.argv[1]) if '"pimc_cf"' in l]
cf = np.array([r["cf"] for r in rows], dtype=float)
est = np.array([r["pimc_cf"] for r in rows], dtype=float)
p1 = np.array([r["pimc_first"] for r in rows], dtype=float)
rule = np.array([bool(r["called"]) for r in rows])
s = [r["state_features"] for r in rows]
partner = np.array([f[163] > 0.5 or f[164] > 0.5 for f in s])
n = len(rows)


def show(name, call):
    v = cf * call
    d = v - cf * rule
    print(f"  {name:44s} calls {100 * call.mean():5.1f}%  {v.mean():+6.2f} ± {v.std() / np.sqrt(n):.2f} pts/decision"
          f"   vs rule {d.mean():+6.2f} ± {d.std() / np.sqrt(n):.2f}")


print(f"{n} Tichu decisions; perfect calling {np.maximum(cf, 0).mean():+.1f}; "
      f"correlation of the simulated estimate with the real value {np.corrcoef(cf, est)[0, 1]:.2f}")
show("current rule", rule)
for m in (-20, -10, 0, 10, 20, 40):
    show(f"simulation: call if estimate > {m}", (est > m) & ~partner)
for t in (0.4, 0.5, 0.6):
    show(f"simulation: call if P(first) >= {t}", (p1 >= t) & ~partner)
show("rule AND simulation estimate > 0", rule & (est > 0))
show("rule OR simulation estimate > 20", (rule | (est > 20)) & ~partner)
