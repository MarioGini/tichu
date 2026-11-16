import 'dart:io';

import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/services/records/file_game_record_store.dart';

GameRecordStore createStore() =>
    // Widget/unit tests must not write into the user's data directory.
    Platform.environment.containsKey('FLUTTER_TEST')
    ? InMemoryGameRecordStore()
    : FileGameRecordStore.defaultLocation();
