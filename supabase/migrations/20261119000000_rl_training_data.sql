-- RL training data (rl/training_data_store.py): rollout-labelled .npz caches
-- in the private Storage bucket "rl-training-data", one manifest row per file.
-- Only the secret / service-role key reads or writes either (RLS on, no
-- policies), so the public app key cannot see or change training data.
--   select run, iteration, kind, decisions, bytes, path
--   from public.rl_training_files order by run, iteration, path;

insert into storage.buckets (id, name, public, file_size_limit)
values ('rl-training-data', 'rl-training-data', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = 52428800;

create table if not exists public.rl_training_files (
    path text primary key,              -- object path in the bucket
    run text not null,                  -- e.g. "v7" (the rollout_loop out-dir name)
    iteration integer,                  -- rollout_loop iteration (itNN_ prefix)
    kind text not null,                 -- "self", "mix0a", "net0b", ...
    decisions integer not null,
    rows integer not null,              -- labelled actions
    bytes bigint not null,
    sha256 text not null,
    policy_sha256 text,                 -- the play net that generated the data
    meta jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default timezone('utc', now())
);

create index if not exists rl_training_files_run_idx
    on public.rl_training_files (run, iteration);

alter table public.rl_training_files enable row level security;
