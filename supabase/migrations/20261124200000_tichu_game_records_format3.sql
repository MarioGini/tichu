-- Game records format 3 (lib/game/record/round_log.dart): one string per
-- round, the initial cards and the move order only. Measured on 40 bot
-- matches to 1000: 140-195 bytes per round, 1.7-3.9 KB per game (format 2:
-- ~480 bytes per round, format 1: ~27 KB). Limits: `log` is an array of
-- strings of at most 400 characters, at most one per round (+1 for the
-- running one), and the record at most 1.5 KB + 300 bytes per round, 32 KB
-- in all.
create or replace function public.tichu_round_logs_valid(log jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select jsonb_typeof(log) = 'array'
       and not exists (
           select 1 from jsonb_array_elements(log) e
           where jsonb_typeof(e) <> 'string'
              or char_length(e #>> '{}') > 400
       );
$$;

alter table public.tichu_game_records
    drop constraint if exists tichu_game_records_record_shape,
    drop constraint if exists tichu_game_records_record_size;

alter table public.tichu_game_records
    add constraint tichu_game_records_record_shape
        check (jsonb_typeof(record) = 'object'
               and record ->> 'id' = id
               and record ->> 'mode' = mode
               and record -> 'format' = '3'
               and public.tichu_round_logs_valid(record -> 'log')
               and jsonb_array_length(record -> 'log')
                   <= coalesce((summary ->> 'rounds')::int, 0) + 1
               and record -> 'targetScore' in ('500', '1000', '1500', '2000')),
    add constraint tichu_game_records_record_size
        check (octet_length(record::text) <= least(
            32000,
            1500 + 300 * (coalesce((summary ->> 'rounds')::int, 0) + 1)));
