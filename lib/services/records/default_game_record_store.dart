import 'package:tichu/game/record/game_record_store.dart';
import 'package:tichu/services/records/default_game_record_store_web.dart'
    if (dart.library.io) 'package:tichu/services/records/default_game_record_store_io.dart'
    as impl;
import 'package:tichu/services/supabase/supabase_app_client.dart';
import 'package:tichu/services/supabase/supabase_game_record_store.dart';

/// The record store the app uses for its games: Supabase
/// (`public.tichu_game_records`) when the build has a Supabase project (the
/// web app on GitHub Pages does), else JSON files on desktop and memory on
/// web. Every game against the bots is then saved and can be reviewed later
/// (`tool/game_record.dart`, `rl/` human-game review).
GameRecordStore createDefaultGameRecordStore() =>
    supabaseConfigured ? SupabaseGameRecordStore() : impl.createStore();
