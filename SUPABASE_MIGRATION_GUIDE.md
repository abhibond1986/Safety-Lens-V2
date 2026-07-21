# SAIL Safety Lens — Supabase Migration Guide

**Goal:** Replace the Google Apps Script + Google Sheets backend with Supabase
(PostgreSQL + Storage), while **keeping** the existing username/password login and
the offline-first design. Incident images move to **Supabase Storage** (fixes the
web/mobile PDF-image problem permanently).

This is written so you can do the Supabase setup yourself (no coding), and I handle
the Flutter/Dart side in phases. Follow the parts marked **YOU DO** in the Supabase
dashboard; the parts marked **I DO** are code changes.

---

## Why Supabase fixes our recurring problems

| Recurring problem | How Supabase fixes it |
|---|---|
| Desktop vs mobile show different data | One Postgres table = single source of truth; every device reads the same rows |
| Deleted incidents keep reappearing on the sheet | A real `DELETE` removes the row permanently; no re-push resurrection |
| PDF has no image on web / older reports | Image stored once in Supabase Storage; every device/platform loads it by URL |
| Sheet is slow / 60-req-min limit / eventual consistency | Postgres is fast, transactional, and consistent |
| No access control | (Later phase) Row-Level Security can enforce who sees/edits what |

---

## Architecture after migration

```
        ┌──────────────────────────────┐
        │        Flutter app           │
        │  (offline-first local cache) │
        └───────────────┬──────────────┘
                        │  supabase_flutter
                        ▼
   ┌────────────────────────────────────────────┐
   │                 Supabase                    │
   │  ┌───────────────┐   ┌────────────────────┐ │
   │  │  PostgreSQL   │   │   Storage bucket   │ │
   │  │  incidents    │   │  incident-images/  │ │
   │  │  users        │   │   img_<id>.jpg     │ │
   │  │  knowledge    │   └────────────────────┘ │
   │  │  master_data  │                          │
   │  └───────────────┘                          │
   └────────────────────────────────────────────┘
```

Local cache (SharedPreferences) stays exactly as it is; only the **remote calls**
in `SyncService` get re-pointed from Apps Script to Supabase.

---

## PHASE 0 — Create the Supabase project (YOU DO, ~15 min)

1. Go to **https://supabase.com** → sign in with GitHub/Google → **New project**.
2. Name it `sail-safety-lens`. Choose the region closest to your users
   (e.g. **South Asia (Mumbai) ap-south-1**). Set a strong database password and
   save it in your password manager.
3. Wait ~2 minutes for provisioning.
4. Open **Project Settings → API**. Copy and keep these two values — you'll paste
   them into the app config later:
   - **Project URL** — looks like `https://xxxxxxxx.supabase.co`
   - **anon public key** — a long `eyJ...` string (safe to ship in the app;
     it only allows what your RLS/policies permit).
   > Do NOT use the `service_role` key in the app — that one bypasses all
   > security and must stay server-side only.

---

## PHASE 1 — Create the database tables (YOU DO, ~5 min)

Open **SQL Editor → New query**, paste the block below, and click **Run**.
This creates every table the app needs, matching the current data shape.

```sql
-- ── INCIDENTS (AI scans + near-miss reports) ──────────────────────────
create table if not exists incidents (
  id              text primary key,          -- app-generated id (millis)
  title           text,
  type            text,                       -- 'AI_SCAN' | 'NEAR_MISS'
  plant           text,
  dept            text,
  location        text,
  detected_section text,
  severity        text,                       -- LOW|MEDIUM|HIGH|CRITICAL
  status          text default 'OPEN',
  wsa_category    text,
  obs_type        text,
  summary         text,
  description     text,
  immediate_action text,
  root_cause      text,
  corrective_action text,
  hazards         jsonb,                       -- array of hazard objects (bbox etc.)
  risk_score      int,
  confidence      int,
  people          int  default 0,
  reported_by     text,
  reported_by_pno text,
  image_url       text,                        -- Supabase Storage public URL
  image_hash      text,
  latitude        double precision,
  longitude       double precision,
  location_accuracy double precision,
  location_address  text,
  location_timestamp text,
  audit_status    text,
  audit_score     int,
  date            timestamptz default now(),
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);
create index if not exists idx_incidents_date  on incidents(date desc);
create index if not exists idx_incidents_plant on incidents(plant);
create index if not exists idx_incidents_pno   on incidents(reported_by_pno);

-- ── USERS (custom auth — password hash kept, NOT Supabase Auth) ────────
create table if not exists app_users (
  username      text primary key,
  name          text,
  designation   text,
  plant         text,
  department    text,
  pno           text,
  mobile        text,
  email         text,
  is_admin      boolean default false,
  status        text default 'active',
  password_hash text,                          -- salted hash from the app
  salt          text,
  created_at    timestamptz default now()
);

-- ── KNOWLEDGE BASE ────────────────────────────────────────────────────
create table if not exists knowledge_docs (
  id         bigint generated always as identity primary key,
  title      text,
  content    text,
  source     text,
  created_at timestamptz default now()
);

-- ── MASTER DATA (plants, depts, WSA causes, etc.) as key→json ─────────
create table if not exists master_data (
  key        text primary key,   -- 'plants' | 'departments' | 'wsa_causes' ...
  value      jsonb,
  updated_at timestamptz default now()
);

-- ── FCM DEVICE TOKENS (push notifications) ────────────────────────────
create table if not exists device_tokens (
  token      text primary key,
  username   text,
  plant      text,
  platform   text,
  created_at timestamptz default now()
);
```

---

## PHASE 2 — Access policies (YOU DO, ~5 min)

For the **first cutover** we keep it simple: since the app uses its own login
(not Supabase Auth), we allow the anon key to read/write these tables. This mirrors
the current "anyone with the app can use it" model of the Sheets backend.

> Security note: this is equivalent to today's setup (the Apps Script URL is public).
> Once the data migration is stable, Phase 6 (later) tightens this with real auth +
> Row-Level Security. Don't skip Phase 6 for production.

Run in **SQL Editor**:

```sql
-- Enable RLS, then add permissive policies for the anon role (temporary).
alter table incidents      enable row level security;
alter table app_users      enable row level security;
alter table knowledge_docs enable row level security;
alter table master_data    enable row level security;
alter table device_tokens  enable row level security;

-- Allow read + write for anon (matches current public-backend behaviour).
create policy anon_all_incidents on incidents
  for all to anon using (true) with check (true);
create policy anon_all_users on app_users
  for all to anon using (true) with check (true);
create policy anon_all_kb on knowledge_docs
  for all to anon using (true) with check (true);
create policy anon_all_master on master_data
  for all to anon using (true) with check (true);
create policy anon_all_tokens on device_tokens
  for all to anon using (true) with check (true);
```

---

## PHASE 3 — Storage bucket for images (YOU DO, ~3 min)

1. **Storage → New bucket** → name `incident-images` → set **Public** (so PDFs and
   web can load the URL directly). Create.
2. Add a policy so the app can upload. **Storage → Policies → New policy** on
   `incident-images`, or run in SQL Editor:

```sql
-- Allow anon to upload and read images in the incident-images bucket.
create policy anon_upload_images on storage.objects
  for insert to anon with check (bucket_id = 'incident-images');
create policy anon_read_images on storage.objects
  for select to anon using (bucket_id = 'incident-images');
```

Images will be stored as `incident-images/img_<incidentId>.jpg`, and each incident
row keeps the public URL in `image_url`.

---

## PHASE 4 — App configuration (I DO, with your keys)

I add the `supabase_flutter` package and a small config. You give me the two values
from Phase 0 (Project URL + anon key). I put them in a config file:

```dart
// lib/services/supabase_config.dart  (I create this)
class SupabaseConfig {
  static const String url     = 'https://xxxxxxxx.supabase.co'; // ← your URL
  static const String anonKey = 'eyJ...';                        // ← your anon key
  static const bool   enabled = true;   // feature flag for safe cutover
}
```

`main()` initializes Supabase at startup. A **feature flag** (`enabled`) lets us
switch between the old Sheets backend and Supabase without ripping anything out —
if something misbehaves, flip it back to `false` and the app uses Sheets again.

---

## PHASE 5 — Code migration (I DO, phased)

I re-point `SyncService`'s remote calls to Supabase, one area at a time, keeping the
offline cache and pending-queue intact:

**Phase 5a — Incidents (first, highest value):**
- `pushIncident`  → upsert into `incidents` (image uploaded to Storage first, URL saved)
- `fetchIncidents` → select from `incidents`
- `deleteIncident` → real `DELETE` (kills the resurrection bug for good)
- `fullSync` → pull all incidents into local cache so every device matches

**Phase 5b — Users:** `pushUser` / `fetchUsers` / `deleteUser` → `app_users` table.
Login still verifies the password hash locally + against `app_users`.

**Phase 5c — Knowledge base & master data:** → `knowledge_docs` / `master_data`.

**Phase 5d — Images everywhere:** the PDF and detail screens already resolve images
through one helper; that helper now returns the Storage URL/bytes, so images appear
on **web and mobile** identically.

Each sub-phase is independently testable and reversible via the feature flag.

---

## PHASE 6 — Harden for production (LATER, recommended)

Once data + images are stable on Supabase:
- Move to **Supabase Auth** (or keep custom login but add per-row ownership).
- Replace the permissive anon policies with **Row-Level Security**: e.g. a user can
  read all incidents but only edit/delete their own; admins can do anything.
- Restrict Storage uploads to authenticated sessions.

I'll write this as a separate step when you're ready — it's not needed to get the
core benefits (consistency + images), but it IS needed before wider rollout.

---

## Data migration (existing Sheet data → Supabase)

You have two options for the incidents already in your Google Sheet:

1. **Fresh start (simplest):** begin clean in Supabase. Old sheet data stays in the
   sheet for reference. Recommended if the current data is mostly test/demo.
2. **One-time import:** export the Sheet's incident tab to CSV, then in Supabase
   **Table editor → incidents → Import data from CSV**, mapping columns to the schema
   above. I can give you an exact column-mapping cheat sheet if you choose this.

---

## Cutover checklist

- [ ] Phase 0–3 done in Supabase dashboard (project, tables, policies, bucket)
- [ ] Sent me the Project URL + anon key
- [ ] I ship Phase 4 + 5a (incidents on Supabase, flag ON) in a test build
- [ ] Verify: scan on mobile → appears on desktop with image; delete → stays deleted
- [ ] Roll forward 5b/5c/5d
- [ ] Plan Phase 6 (auth + RLS) before production rollout

---

## Rollback

If anything goes wrong at any point: set `SupabaseConfig.enabled = false`. The app
immediately reverts to the Google Sheets backend — no data loss, no redeploy of
Supabase needed. This is why we keep both paths during cutover.

---

## What I need from you to start Phase 1 build

1. Run Phase 0–3 in the Supabase dashboard.
2. Send me the **Project URL** and **anon public key**.

With those, I'll wire up `SupabaseService` + the incidents path behind the feature
flag so you can test cross-device consistency and images end-to-end.
