import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/services/records/default_game_record_store_web.dart'
    if (dart.library.io) 'package:tichu/services/records/default_game_record_store_io.dart'
    as impl;

/// The record store the app uses: JSON files on desktop, memory on web.
GameRecordStore createDefaultGameRecordStore() => impl.createStore();
