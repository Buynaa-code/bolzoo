-- Notifications outbox: one row per (invite_id, kind). The unique constraint
-- gives idempotency — a POST /api/notify-response retry cannot cause a second
-- email. sent_at is null while pending; error captures the last failure so a
-- future cron/retry job can pick pending rows up.

create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  invite_id   text not null references public.invites(id) on delete cascade,
  kind        text not null,
  to_email    text not null,
  sent_at     timestamptz,
  error       text,
  created_at  timestamptz not null default now(),
  unique (invite_id, kind)
);

create index if not exists notifications_invite_id_idx on public.notifications(invite_id);
create index if not exists notifications_pending_idx  on public.notifications(created_at)
  where sent_at is null;

alter table public.notifications enable row level security;

revoke all on table public.notifications from public, anon, authenticated;
grant select, insert, update, delete on table public.notifications to service_role;

notify pgrst, 'reload schema';
