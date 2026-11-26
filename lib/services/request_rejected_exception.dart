/// A lobby or match request the table services refuse: an unknown lobby,
/// match or access token, a taken seat, a stale revision, a request only
/// the host may make... The caller asked for something that is not
/// possible now; the authority server answers it with 400.
class RequestRejectedException implements Exception {
  const RequestRejectedException(this.message);

  final String message;

  @override
  String toString() => 'Request rejected: $message';
}
