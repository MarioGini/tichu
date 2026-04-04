# lib/headless/

Non-UI execution path for scripted or batch game simulations.

## Implemented Here
- `headless.dart`: deterministic self-play runner over the core engine.

## Modes
- `--format=csv` (default): event log compatible with existing headless CSV workflows.
- `--format=rl-jsonl`: transition-oriented JSONL output for RL-style training pipelines.
- `--format=none`: simulation only, no file output.

## RL Data Contract
- Transition schema: `tichu_rl_transition_v2`.
- Includes `state`, `action`, `next_state`, `reward`, `done`, and `discount`.
- Includes `state_key`/`next_state_key` and `action_key` for compact table-based training.
- Emits `legal_action_keys` and `action_index` when the phase/action space is enumerable.

## Policy Hook
- `--rl-policy=policy.json` loads a state/action-value table.
- The loaded policy is applied through existing AI interfaces:
	`SmartAiAgent(playSelectionStrategy: RlPolicyPlaySelectionStrategy(...))`.
- Missing states/actions automatically fall back to default heuristic play selection.

## Policy Build Tool
- Build policy from transitions:
	`dart run tool/rl/build_policy_from_transitions.dart --input=trajectories.jsonl --output=policy.json`
- Policy schema reference:
	`tool/rl/policy.schema.json`
- Tool guide:
	`tool/rl/README.md`

## Throughput
- Uses a direct engine loop (no backend stream/confirmation round-trips), so long runs are more stable and faster.
- Supports `--episodes`, `--rounds`, and `--max-steps` for controlled high-volume simulation.
