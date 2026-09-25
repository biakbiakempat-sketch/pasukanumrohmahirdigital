# Supabase — Live Contract

## Source of truth

- **Live source branch:** `supabase-live-v1`
- **Deployment:** GitHub Pages from `supabase-live-v1`
- **Public app:** `https://biakbiakempat-sketch.github.io/pasukanumrohmahirdigital/`
- **Supabase project:** `insciufudobddaqzxzil`
- **Supabase status at sync:** ACTIVE_HEALTHY
- **Database:** PostgreSQL 17

## Important

The live database was created outside Supabase migration history, so the migration list is currently empty. Do **not** assume the old SQL files are the live schema.

`supabase/phase1.sql` is **legacy** and targets the old `app_members` architecture. It must not be executed against the live project.

## Live tables

`profiles`, `member_sessions`, `member_leads`, `member_closings`, `member_checklists`, `program_configs`, `leads`, `sales_activities`, `closings`, `checklists`, `rewards`, `schedules`, `info_bars`, `popups`.

## RPCs used by the current web app

The current `index.html` calls these 25 RPCs, and all 25 exist in the live Supabase project:

- `admin_central_snapshot`
- `admin_config_get`
- `admin_config_save`
- `admin_lead_delete`
- `admin_lead_upsert`
- `member_activity_list`
- `member_activity_upsert`
- `member_admin_create`
- `member_admin_delete`
- `member_admin_update`
- `member_approve`
- `member_checklist_get`
- `member_checklist_save`
- `member_closing_delete`
- `member_closing_upsert`
- `member_closings_list`
- `member_config_get`
- `member_lead_delete`
- `member_lead_upsert`
- `member_leads_list`
- `member_login`
- `member_register`
- `member_reject`
- `member_session_logout`
- `member_set_day`

The live database also contains supporting functions such as `central_member_id`, `is_super_admin`, `central_set_updated_at`, `protect_profile_fields`, `admin_closing_upsert`, and `admin_closing_delete`.

## Current login contract

- Super Admin authenticates through Supabase Auth.
- Member registration/login uses `member_register` / `member_login`.
- The application points to the live Supabase project `insciufudobddaqzxzil`.
- The app must not contain `service_role` or `sb_secret_` credentials.

## Update rule

When the application changes:

1. Change **only** `supabase-live-v1` unless explicitly instructed otherwise.
2. Keep desktop and mobile behavior in the same `index.html`.
3. GitHub Pages deploys from `supabase-live-v1`.
4. If the database contract changes, update the live Supabase project and this document in the same change window.
5. Never run `supabase/phase1.sql` on the live database.
