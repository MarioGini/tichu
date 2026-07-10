part of 'headless.dart';

/// Emits one JSONL record per completed match. Used by `--format=summary`,
/// which is what `evaluate_policy.py` consumes when it only needs win/loss
/// totals (not the per-step transition stream). Skipping the per-transition
/// JSON encode-and-write cost cuts headless eval wallclock by ~6×.
class _SummaryWriter {
  final IOSink output;
  final int episode;
  var _emitted = false;

  _SummaryWriter({required this.output, required this.episode});

  void emit(final GameSnapshot snapshot) {
    if (_emitted) return;
    _emitted = true;
    final score = snapshot.scoreState;
    final t1 = score.teamOneTotal;
    final t2 = score.teamTwoTotal;
    final winner = score.winningTeam;
    output.writeln(
      jsonEncode(<String, Object?>{
        'episode': episode,
        'team_one_total': t1,
        'team_two_total': t2,
        'winner': winner,
        'rounds': score.roundNumber,
        'finish_order': score.finishOrder,
        'done': score.gameComplete,
      }),
    );
  }
}
