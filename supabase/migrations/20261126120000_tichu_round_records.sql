-- One row per round of a game record, so a round can be looked up directly
-- by its id (or the first 8 characters, `short_id`):
--   select * from public.tichu_round_records where short_id = '<8 chars>';
-- `log` is the round's format-3 string (lib/game/record/round_log.dart),
-- the same as the game's `record -> 'log' -> (round - 1)`. The app upserts
-- the running round as it is played (on conflict (game_id, round)) and sets
-- the round points once it is over.
create table if not exists public.tichu_round_records (
    id uuid primary key,
    short_id text generated always as (left(id::text, 8)) stored,
    game_id text not null
        references public.tichu_game_records (id) on delete cascade,
    round integer not null,
    log text not null,
    complete boolean not null default false,
    team_one_points integer,
    team_two_points integer,
    owner uuid default auth.uid(),
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now()),
    constraint tichu_round_records_game_round unique (game_id, round),
    constraint tichu_round_records_round check (round between 1 and 200),
    constraint tichu_round_records_log_size check (char_length(log) <= 400),
    constraint tichu_round_records_points check (
        team_one_points is null
        or team_one_points between -1000 and 1000),
    constraint tichu_round_records_points_two check (
        team_two_points is null
        or team_two_points between -1000 and 1000)
);

create index if not exists tichu_round_records_short_id_idx
    on public.tichu_round_records (short_id);

alter table public.tichu_round_records enable row level security;

drop policy if exists "round records: owner reads" on public.tichu_round_records;
create policy "round records: owner reads" on public.tichu_round_records
    for select to authenticated using (owner = auth.uid());

-- A round may only be added to a game the same user owns.
drop policy if exists "round records: owner inserts" on public.tichu_round_records;
create policy "round records: owner inserts" on public.tichu_round_records
    for insert to authenticated with check (
        owner = auth.uid()
        and exists (
            select 1 from public.tichu_game_records g
            where g.id = game_id and g.owner = auth.uid()));

drop policy if exists "round records: owner updates" on public.tichu_round_records;
create policy "round records: owner updates" on public.tichu_round_records
    for update to authenticated
    using (owner = auth.uid())
    with check (
        owner = auth.uid()
        and exists (
            select 1 from public.tichu_game_records g
            where g.id = game_id and g.owner = auth.uid()));

-- Backfill the games stored so far (round points are not stored there;
-- they follow from the replay).
insert into public.tichu_round_records
    (id, game_id, round, log, complete, owner, created_at, updated_at)
select gen_random_uuid(), g.id, l.n::int, l.log #>> '{}',
       g.complete or l.n < jsonb_array_length(g.record -> 'log'),
       g.owner, g.created_at, g.updated_at
from public.tichu_game_records g
cross join lateral jsonb_array_elements(g.record -> 'log')
    with ordinality as l(log, n)
where jsonb_typeof(g.record -> 'log') = 'array'
on conflict (game_id, round) do nothing;
