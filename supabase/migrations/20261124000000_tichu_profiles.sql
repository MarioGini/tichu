-- Player profiles, one row per auth user (anonymous for now). The app
-- creates its row on first launch and renames it from the home screen; the
-- anonymous session that supabase_flutter keeps on the device brings the
-- same user (and profile) back on later launches. Linking Google / e-mail
-- later keeps the user id, so the profile carries over.
create table if not exists public.tichu_profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null
        check (char_length(display_name) between 1 and 24),
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

alter table public.tichu_profiles enable row level security;

drop policy if exists "profiles: owner reads" on public.tichu_profiles;
create policy "profiles: owner reads" on public.tichu_profiles
    for select to authenticated using (id = (select auth.uid()));

drop policy if exists "profiles: owner inserts" on public.tichu_profiles;
create policy "profiles: owner inserts" on public.tichu_profiles
    for insert to authenticated with check (id = (select auth.uid()));

drop policy if exists "profiles: owner updates" on public.tichu_profiles;
create policy "profiles: owner updates" on public.tichu_profiles
    for update to authenticated
    using (id = (select auth.uid())) with check (id = (select auth.uid()));
