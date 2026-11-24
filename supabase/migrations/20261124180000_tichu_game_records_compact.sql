-- Game records are stored in format 2 (lib/game/record/round_log.dart): a
-- compact log per round instead of the full event list. Measured on 40 bot
-- matches to 1000: 398-547 bytes per round, 3-11 KB per game (format 1:
-- ~27 KB per round). Tighten the limits of the previous migration to match:
-- a `log` array with at most one entry per round (+1 for the running one),
-- 1000 bytes per round plus 2 KB for the header, 100 KB in all.
alter table public.tichu_game_records
    drop constraint if exists tichu_game_records_record_shape,
    drop constraint if exists tichu_game_records_record_size;

alter table public.tichu_game_records
    add constraint tichu_game_records_record_shape
        check (jsonb_typeof(record) = 'object'
               and record ->> 'id' = id
               and record ->> 'mode' = mode
               and record -> 'format' = '2'
               and jsonb_typeof(record -> 'log') = 'array'
               and jsonb_array_length(record -> 'log')
                   <= coalesce((summary ->> 'rounds')::int, 0) + 1
               and record -> 'targetScore' in ('500', '1000', '1500', '2000')),
    add constraint tichu_game_records_record_size
        check (octet_length(record::text) <= least(
            100000,
            2000 + 1000 * (coalesce((summary ->> 'rounds')::int, 0) + 1)));
