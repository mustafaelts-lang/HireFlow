# Supabase (HireFlow)

Schema and migrations for HireFlow live here (see `docs/DATABASE_DESIGN.md` and `docs/ROADMAP.md`).

## Layout

- `migrations/` — ordered SQL migrations
- `seed.sql` — optional local seed (empty by default)
- `config.toml` — Supabase CLI config

## Required environment variables

Already used by the web app:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`

Required to **apply** migrations / privileged server access (not yet in `apps/web/.env.local`):

- `SUPABASE_SERVICE_ROLE_KEY` — server-side admin API (bypasses RLS)
- `DATABASE_URL` — Postgres connection string (Session mode / direct) used by `supabase db push`

Optional for CLI linking:

- `SUPABASE_ACCESS_TOKEN` — personal access token for `supabase login` / CI

## Apply migrations (after secrets are set)

From repo root:

```bash
npx supabase link --project-ref <project-ref> --workdir infrastructure
npx supabase db push --workdir infrastructure
```

Or with a direct DB URL:

```bash
npx supabase db push --workdir infrastructure --db-url "$DATABASE_URL"
```

## Helpers created by the baseline migration

- `public.create_tenant(name, slug, owner_user_id, ...)` — creates tenant, seeds pipeline stages, owner membership
- `public.seed_default_pipeline_stages(tenant_id)`
- `public.seed_pre_hire_checklist(application_id)`
