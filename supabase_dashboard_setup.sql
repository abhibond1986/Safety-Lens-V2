-- ═══════════════════════════════════════════════════════════════════════════
--  SAIL Safety Lens — Supabase one-time setup
--  Run this ONCE in the Supabase dashboard: SQL Editor → New query → paste →
--  Run.  Safe to re-run (uses IF NOT EXISTS / idempotent statements).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── STEP 1 : Storage bucket for incident evidence photos ────────────────────
-- Creates the public "incident-images" bucket the app uploads to.
insert into storage.buckets (id, name, public)
values ('incident-images', 'incident-images', true)
on conflict (id) do update set public = true;

-- Allow the app (anon key) to read / upload / overwrite / delete images in it.
drop policy if exists "incident-images read"   on storage.objects;
drop policy if exists "incident-images write"  on storage.objects;
drop policy if exists "incident-images update" on storage.objects;
drop policy if exists "incident-images delete" on storage.objects;

create policy "incident-images read"
  on storage.objects for select
  using (bucket_id = 'incident-images');

create policy "incident-images write"
  on storage.objects for insert
  with check (bucket_id = 'incident-images');

create policy "incident-images update"
  on storage.objects for update
  using (bucket_id = 'incident-images');

create policy "incident-images delete"
  on storage.objects for delete
  using (bucket_id = 'incident-images');

-- ── STEP 2 : Realtime for the incidents table ──────────────────────────────
-- Add the incidents table to the realtime publication (add-only; won't
-- disturb any tables already published).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'incidents'
  ) then
    alter publication supabase_realtime add table incidents;
  end if;
end $$;

-- Ensure DELETE events carry the full old row (so a delete on one device
-- correctly disappears on all other devices).
alter table incidents replica identity full;
