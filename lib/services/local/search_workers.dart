import 'package:tichu/agents/endgame_search.dart';
import 'package:tichu/services/local/search_workers_web.dart'
    if (dart.library.io) 'package:tichu/services/local/search_workers_io.dart'
    as impl;

/// Where the app's endgame search rolls out its worlds: background
/// isolates on phones and desktop (one batch per spare core, at most 4),
/// on the UI isolate on the web (no isolates there).
WorldTaskRunner? get searchWorldRunner => impl.searchWorldRunner;

int get searchParallelism => impl.searchParallelism;
