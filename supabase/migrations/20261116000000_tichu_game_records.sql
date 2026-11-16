-- Game records (observe mode and solo games), one row per game.
-- Written by the app (anonymous auth user, owner = auth.uid()) and by the
-- Dart authority (service role). Look one up with:
--   select record from public.tichu_game_records where id = '<game id>';
create table if not exists public.tichu_game_records (
    id text primary key,
    mode text not null,
    complete boolean not null default false,
    summary jsonb not null,
    record jsonb not null,
    owner uuid default auth.uid(),
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

alter table public.tichu_game_records
    add column if not exists owner uuid default auth.uid();
alter table public.tichu_game_records
    alter column owner set default auth.uid();

create index if not exists tichu_game_records_updated_at_idx
    on public.tichu_game_records (updated_at desc);

alter table public.tichu_game_records enable row level security;

drop policy if exists "game records: owner reads" on public.tichu_game_records;
create policy "game records: owner reads" on public.tichu_game_records
    for select to authenticated using (owner = auth.uid());

drop policy if exists "game records: owner inserts" on public.tichu_game_records;
create policy "game records: owner inserts" on public.tichu_game_records
    for insert to authenticated with check (owner = auth.uid());

drop policy if exists "game records: owner updates" on public.tichu_game_records;
create policy "game records: owner updates" on public.tichu_game_records
    for update to authenticated
    using (owner = auth.uid()) with check (owner = auth.uid());
