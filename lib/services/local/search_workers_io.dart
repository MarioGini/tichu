import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:tichu/agents/endgame_search.dart';

WorldTaskRunner? get searchWorldRunner => Isolate.run;

int get searchParallelism => max(1, min(4, Platform.numberOfProcessors - 1));
