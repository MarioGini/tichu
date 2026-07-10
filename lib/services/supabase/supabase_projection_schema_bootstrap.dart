import 'package:postgres/postgres.dart';

class SupabaseProjectionSchemaBootstrap {
  SupabaseProjectionSchemaBootstrap({required final String databaseUrl})
    : _databaseUrl = databaseUrl;

  final String _databaseUrl;

  static const List<String> _statements = <String>[
    '''
create table if not exists public.tichu_lobby_views (
    lobby_id text not null,
    access_token text not null,
    player_id text not null,
    payload jsonb not null,
    updated_at timestamptz not null default timezone('utc', now()),
    primary key (lobby_id, access_token)
)
''',
    '''
create table if not exists public.tichu_match_player_views (
    match_id text not null,
    access_token text not null,
    lobby_id text not null,
    player_id text not null,
    revision integer not null,
    payload jsonb not null,
    updated_at timestamptz not null default timezone('utc', now()),
    primary key (match_id, access_token)
)
''',
    '''
create table if not exists public.tichu_match_connection_views (
    match_id text not null,
    access_token text not null,
    lobby_id text not null,
    player_id text not null,
    payload jsonb not null,
    updated_at timestamptz not null default timezone('utc', now()),
    primary key (match_id, access_token)
)
''',
    '''
alter table public.tichu_lobby_views
    add column if not exists auth_user_id text
''',
    '''
alter table public.tichu_match_player_views
    add column if not exists auth_user_id text
''',
    '''
alter table public.tichu_match_connection_views
    add column if not exists auth_user_id text
''',
    '''
update public.tichu_lobby_views
set auth_user_id = coalesce(auth_user_id, player_id, access_token)
where auth_user_id is null
''',
    '''
update public.tichu_match_player_views
set auth_user_id = coalesce(auth_user_id, player_id, access_token)
where auth_user_id is null
''',
    '''
update public.tichu_match_connection_views
set auth_user_id = coalesce(auth_user_id, player_id, access_token)
where auth_user_id is null
''',
    '''
alter table public.tichu_lobby_views
    alter column auth_user_id set not null
''',
    '''
alter table public.tichu_match_player_views
    alter column auth_user_id set not null
''',
    '''
alter table public.tichu_match_connection_views
    alter column auth_user_id set not null
''',
    '''
create index if not exists tichu_lobby_views_player_idx
    on public.tichu_lobby_views (player_id)
''',
    '''
create index if not exists tichu_match_player_views_player_idx
    on public.tichu_match_player_views (player_id)
''',
    '''
create index if not exists tichu_match_player_views_revision_idx
    on public.tichu_match_player_views (match_id, revision desc)
''',
    '''
create index if not exists tichu_match_connection_views_player_idx
    on public.tichu_match_connection_views (player_id)
''',
    '''
create index if not exists tichu_lobby_views_auth_user_idx
    on public.tichu_lobby_views (auth_user_id)
''',
    '''
create index if not exists tichu_match_player_views_auth_user_idx
    on public.tichu_match_player_views (auth_user_id)
''',
    '''
create index if not exists tichu_match_connection_views_auth_user_idx
    on public.tichu_match_connection_views (auth_user_id)
''',
    '''
alter table public.tichu_lobby_views replica identity full
''',
    '''
alter table public.tichu_match_player_views replica identity full
''',
    '''
alter table public.tichu_match_connection_views replica identity full
''',
    '''
grant select on public.tichu_lobby_views to authenticated
''',
    '''
grant select on public.tichu_match_player_views to authenticated
''',
    '''
grant select on public.tichu_match_connection_views to authenticated
''',
    '''
revoke select on public.tichu_lobby_views from anon
''',
    '''
revoke select on public.tichu_match_player_views from anon
''',
    '''
revoke select on public.tichu_match_connection_views from anon
''',
    '''
grant all on public.tichu_lobby_views to service_role
''',
    '''
grant all on public.tichu_match_player_views to service_role
''',
    '''
grant all on public.tichu_match_connection_views to service_role
''',
    '''
alter table public.tichu_lobby_views enable row level security
''',
    '''
alter table public.tichu_match_player_views enable row level security
''',
    '''
alter table public.tichu_match_connection_views enable row level security
''',
    '''
drop policy if exists tichu_lobby_views_select_own on public.tichu_lobby_views
''',
    '''
create policy tichu_lobby_views_select_own
    on public.tichu_lobby_views
    for select
    to authenticated
    using (auth.uid()::text = auth_user_id)
''',
    '''
drop policy if exists tichu_match_player_views_select_own on public.tichu_match_player_views
''',
    '''
create policy tichu_match_player_views_select_own
    on public.tichu_match_player_views
    for select
    to authenticated
    using (auth.uid()::text = auth_user_id)
''',
    '''
drop policy if exists tichu_match_connection_views_select_own on public.tichu_match_connection_views
''',
    '''
create policy tichu_match_connection_views_select_own
    on public.tichu_match_connection_views
    for select
    to authenticated
    using (auth.uid()::text = auth_user_id)
''',
    '''
create table if not exists public.tichu_authority_lobbies (
    lobby_id text primary key,
    state jsonb not null,
    updated_at timestamptz not null default timezone('utc', now())
)
''',
    '''
create table if not exists public.tichu_authority_actions (
    match_id text not null,
    lobby_id text not null,
    seq integer not null,
    action jsonb not null,
    created_at timestamptz not null default timezone('utc', now()),
    primary key (match_id, seq)
)
''',
    '''
create index if not exists tichu_authority_actions_match_idx
    on public.tichu_authority_actions (match_id, seq asc)
''',
    '''
grant all on public.tichu_authority_lobbies to service_role
''',
    '''
grant all on public.tichu_authority_actions to service_role
''',
    '''
revoke all on public.tichu_authority_lobbies from anon
''',
    '''
revoke all on public.tichu_authority_actions from anon
''',
    '''
revoke all on public.tichu_authority_lobbies from authenticated
''',
    '''
revoke all on public.tichu_authority_actions from authenticated
''',
  ];

  Future<void> ensureReady() async {
    final connection = await Connection.openFromUrl(_databaseUrl);
    try {
      await connection.runTx((final session) async {
        for (final statement in _statements) {
          await session.execute(statement);
        }
      });
    } finally {
      await connection.close();
    }
  }
}
