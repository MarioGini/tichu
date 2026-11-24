-- Limits on game records uploaded by the app, so anonymous users cannot
-- fill the database. Measured on 40 bot matches to 1000 (observe mode):
-- 24.7-28.0 KB of record JSON per round, 5-19 rounds, 140-530 KB per game,
-- summaries <= 229 bytes. Matches to 2000 run about twice as many rounds.
--
-- * record: at most 40 KB per round (rounds + 1, so an unfinished round
--   fits) and 2 MB in all;
-- * summary: at most 1 KB;
-- * shape: JSON objects whose id / mode match the row, an events array,
--   a target score the app offers;
-- * at most 2000 games per owner (the Dart authority writes with the
--   service role and no owner, so it is not limited).
alter table public.tichu_game_records
    drop constraint if exists tichu_game_records_id_len,
    drop constraint if exists tichu_game_records_mode,
    drop constraint if exists tichu_game_records_summary_size,
    drop constraint if exists tichu_game_records_record_shape,
    drop constraint if exists tichu_game_records_record_size;

alter table public.tichu_game_records
    add constraint tichu_game_records_id_len
        check (char_length(id) between 1 and 64),
    add constraint tichu_game_records_mode
        check (mode in ('observe', 'play')),
    add constraint tichu_game_records_summary_size
        check (jsonb_typeof(summary) = 'object'
               and octet_length(summary::text) <= 1024),
    add constraint tichu_game_records_record_shape
        check (jsonb_typeof(record) = 'object'
               and record ->> 'id' = id
               and record ->> 'mode' = mode
               and jsonb_typeof(record -> 'events') = 'array'
               and record -> 'targetScore' in ('500', '1000', '1500', '2000')),
    add constraint tichu_game_records_record_size
        check (octet_length(record::text) <= least(
            2000000,
            40000 * (coalesce((summary ->> 'rounds')::int, 0) + 1)));

create or replace function public.tichu_game_records_owner_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.owner is not null and (
        select count(*) from public.tichu_game_records where owner = new.owner
    ) >= 2000 then
        raise exception 'game record quota reached (2000 per player)'
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

revoke all on function public.tichu_game_records_owner_quota() from public, anon, authenticated;

drop trigger if exists tichu_game_records_owner_quota on public.tichu_game_records;
create trigger tichu_game_records_owner_quota
    before insert on public.tichu_game_records
    for each row execute function public.tichu_game_records_owner_quota();
