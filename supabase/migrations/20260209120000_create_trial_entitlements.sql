-- Create trial_entitlements table
create table if not exists trial_entitlements (
  id uuid primary key default gen_random_uuid(),
  device_id text not null,
  account_hash text,
  started_at timestamptz not null,
  expires_at timestamptz not null,
  consumed boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Indexes for performance and uniqueness constraints
create unique index if not exists uq_trial_device on trial_entitlements(device_id);
create unique index if not exists uq_trial_account on trial_entitlements(account_hash) where account_hash is not null;

-- Enable Row Level Security (RLS)
alter table trial_entitlements enable row level security;

-- Policy: Allow service role full access (Edge Functions use service role)
-- No public policies are added, meaning public anon access is denied by default.
create policy "Service role has full access"
  on trial_entitlements
  for all
  to service_role
  using (true)
  with check (true);
