# lib/services/local/

Local-first backend implementation for gameplay runtime.

## Implemented Here
- `local_match_runtime.dart`: local in-process runtime that owns engine state and AI turn orchestration for a single match.
- `local_table_service.dart`: local implementation of `GameSessionService` and `GameMatchService` for lobby and match flows without a cloud transport.
