# Product Roadmap

**Product:** HireFlow  
**Purpose:** Phased plan from documentation foundation → recruiter MVP → multi-tenant SaaS.  
**Status:** Baseline (source of truth) — aligned with IMPLEMENTATION_PLAN.md (2026-08-04)

This roadmap sequences delivery so the product is useful early without painting the architecture into a corner.

---

## 0. Guiding roadmap rules

1. **Docs before code** — workflow and data model accepted before scaffolding.
2. **Vertical slices** — ship end-to-end recruiter workflows, not horizontal-only layers.
3. **Multi-tenant data from day one** — even while only one company uses the MVP.
4. **Real HR process fidelity** — stages match department request → hire → regret letters.
5. **One Recruiter MVP** — defer HM/Interviewer logins until the single-recruiter loop is excellent.
6. **No candidate accounts** — public apply only for inbound.
7. **Integrations after core truth** — calendar/email automation follow pipeline correctness.

---

## Phase 0 — Foundation & workflow alignment (current complete)

**Objective:** Professional repository structure and documentation baseline matching the real HR process.

| Deliverable                       | Status |
| --------------------------------- | ------ |
| Repository folder structure       | Done   |
| IMPLEMENTATION_PLAN.md            | Done   |
| PRODUCT_REQUIREMENTS.md (aligned) | Done   |
| RECRUITMENT_WORKFLOW.md (aligned) | Done   |
| USER_ROLES.md (aligned)           | Done   |
| SYSTEM_ARCHITECTURE.md            | Done   |
| DATABASE_DESIGN.md (aligned)      | Done   |
| UI_GUIDELINES.md (aligned)        | Done   |
| ROADMAP.md (aligned)              | Done   |

**Exit criteria:** Stakeholders accept `/docs` (including IMPLEMENTATION_PLAN.md) as the source of truth for MVP implementation.

---

## Phase 1 — Platform skeleton

**Objective:** Runnable app shells with auth, tenancy, and database migrations — still thin on recruiting features.

### Scope

- Initialize `apps/api` and `apps/web` per SYSTEM_ARCHITECTURE.md / IMPLEMENTATION_PLAN §8
- PostgreSQL schema migrations for core tables in DATABASE_DESIGN.md
- Tenant + user + membership provisioning
- Authentication (login / logout / session) for Recruiter
- Seed default `pipeline_stages` on tenant create
- Health checks, env config, local Docker Compose (Postgres + S3-compatible storage)
- CI lint/test placeholders
- Automated test: API rejects cross-tenant access

### Exit criteria

- Recruiter can sign in to a provisioned tenant
- API rejects cross-tenant access in automated tests
- Empty authenticated app shell loads

---

## Phase 2 — Jobs & public apply

**Objective:** Requisition → JD → publish, plus unauthenticated inbound applications.

### Scope

- Jobs CRUD + statuses (`draft`, `open`, `on_hold`, `closed`, `filled`)
- Request metadata (department, requester, HM name/email)
- Publish action → `public_apply_token` + `apply_enabled`
- Public apply page (no candidate account)
- Resume upload + consent capture
- Candidate dedupe by email
- Manual candidate/application entry

### Exit criteria

- Recruiter publishes a job and copies apply link
- Candidate submits public form; application appears in `applied`
- Closed/on_hold/filled jobs reject new applies

---

## Phase 3 — Selection pipeline

**Objective:** Recruiter runs CV → phone → interview → references with full history.

### Scope

- Pipeline board + list/filter views
- Stage transitions with validation + `application_stage_events`
- Stages: `cv_screening`, `phone_screening`, `interview`, `reference_check`
- Interviews + feedback (including on-behalf-of HM)
- `reference_checks` records
- Reject with reason codes

### Exit criteria

- Multiple candidates movable through selection stages
- Interview scheduled + feedback saved
- Full stage history visible per application

---

## Phase 4 — Offer, pre-hire, hire, regret (MVP complete)

**Objective:** Close the real hire loop and rejection communications.

### Scope

- `offers` CRUD + statuses
- Accept → `pre_hire` + seeded checklist
- Checklist completion + file attachments
- Transition to `hired`; job fill prompt
- `communications` log for regret letters
- Bulk “reject remaining when filled” helper (Should)
- Basic dashboard (open jobs, upcoming interviews)
- Search candidates by name/email

### Exit criteria

Matches PRODUCT_REQUIREMENTS.md MVP acceptance criteria (department request → public apply → full pipeline → hire + regret log).

**This phase completes the customer-usable Recruiter MVP.**

---

## Phase 5 — Multi-user collaboration

**Objective:** Expand beyond a single recruiter inside a tenant.

### Scope

- Invite users; assign roles (`hiring_manager`, `interviewer`, `company_admin`)
- Job assignment / visibility scoping
- Hiring Manager submits own feedback
- Admin settings for users and company profile
- Stronger audit log UI

### Exit criteria

- Recruiter and hiring manager collaborate on one job without sharing a login
- Permission matrix from USER_ROLES.md enforced in API tests

---

## Phase 6 — Multi-tenant SaaS readiness

**Objective:** Operate HireFlow as a product for many companies.

### Scope

- Self-serve tenant signup (or assisted onboarding tooling)
- Tenant suspension / reactivation
- Platform admin support tools
- Usage limits & basic plan entitlements
- Billing integration (seats or subscription)
- Backups, monitoring alerts, production runbooks
- RLS evaluation / hardening pass

### Exit criteria

- Two isolated tenants operate concurrently with zero data leakage (verified tests)
- New tenant provisioned through a documented onboarding path
- Basic paid plan can be activated

---

## Phase 7 — Communications automation & candidate experience polish

**Objective:** Reduce manual outbound work; improve inbound quality.

### Scope

- Automated email for regret / offer / stage notices (configurable)
- Apply-form hardening (CAPTCHA if needed)
- Candidate duplicate handling improvements
- Optional lightweight candidate status page (still no full account required)

### Exit criteria

- Regret/offer emails can send from the system when enabled
- Recruiter can rely less on external mail clients for standard notices

---

## Phase 8 — Workflow power-ups

**Objective:** Make HireFlow adaptable to different hiring processes.

### Scope

- Custom stages per tenant (labels, order, enable/disable)
- Transition checklists / required fields
- Richer offer compensation fields
- CSV import/export maturity
- Saved views / advanced filters
- Aging SLAs and nudges from RECRUITMENT_WORKFLOW.md
- Optional e-sign provider

---

## Phase 9 — Integrations & intelligence

**Objective:** Connect HireFlow to existing tools; add selective intelligence.

### Scope

- Google/Outlook calendar sync
- Email provider deeper threading
- Slack/Teams notifications
- Webhooks / public API
- Optional AI assist: resume parsing, draft rejection notes, interview question suggestions
- Analytics dashboards (time-to-hire, source quality)

**Rule:** AI features assist; they do not silently make hiring decisions.

---

## Priority view (summary)

```text
Phase 0  Foundation docs & workflow alignment     ← complete
Phase 1  Auth + tenancy + schema
Phase 2  Jobs + public apply
Phase 3  Selection pipeline
Phase 4  Offer / pre-hire / hire / regret         ← first customer-usable MVP
Phase 5  Multi-user roles (HM login)
Phase 6  Commercial multi-tenant SaaS
Phase 7  Email automation & apply polish
Phase 8  Custom workflows
Phase 9  Integrations + AI assists
```

---

## Milestone metrics (suggested)

| Milestone     | Leading metrics                                        |
| ------------- | ------------------------------------------------------ |
| MVP launch    | Time for recruiter to process 10 candidates on 1 job   |
| Collaboration | % interviews with written feedback from HM user        |
| Multi-tenant  | Zero cross-tenant incidents; tenant create time        |
| Inbound       | % applications via public apply vs manual              |
| Scale         | Weekly active recruiters; jobs filled through HireFlow |

---

## Decision log (living)

Record major product/tech decisions here as they are made.

| Date       | Decision                                              | Rationale                                                                       |
| ---------- | ----------------------------------------------------- | ------------------------------------------------------------------------------- |
| 2026-08-04 | Shared-schema multi-tenancy with `tenant_id`          | Fast MVP, scalable enough, isolation via strict query discipline (+ future RLS) |
| 2026-08-04 | Modular monolith (web + api)                          | Avoid microservice overhead before product-market fit                           |
| 2026-08-04 | MVP user = single recruiter                           | Fastest path to validating the hiring loop                                      |
| 2026-08-04 | Public apply in MVP; no candidate accounts            | Matches real inbound process; avoids portal scope                               |
| 2026-08-04 | Fine-grained stages (CV, phone, references, pre-hire) | Reflects real HR workflow; clearer ops than coarse “screening”                  |
| 2026-08-04 | Offer + checklist + communications as entities        | Hire is not “offer sent”; regret letters must be trackable                      |
| 2026-08-04 | HM offline in MVP (job fields + on-behalf feedback)   | Defer collaboration complexity without losing evaluation records                |
| 2026-08-04 | Next.js monorepo + Supabase (Phase 1 scaffold)        | `apps/web` + `packages/shared`; Supabase clients; schema home in `infrastructure/supabase` |

---

## Immediate next actions

1. Copy `apps/web/.env.example` → `apps/web/.env.local` and set Supabase keys.
2. Continue Phase 1: schema migrations + tenancy/auth (still no ATS features until later phases).
3. Keep `/docs` frozen unless implementation forces a decision update.

---

## Related documents

- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)
- [PRODUCT_REQUIREMENTS.md](./PRODUCT_REQUIREMENTS.md)
- [RECRUITMENT_WORKFLOW.md](./RECRUITMENT_WORKFLOW.md)
- [USER_ROLES.md](./USER_ROLES.md)
- [SYSTEM_ARCHITECTURE.md](./SYSTEM_ARCHITECTURE.md)
- [DATABASE_DESIGN.md](./DATABASE_DESIGN.md)
- [UI_GUIDELINES.md](./UI_GUIDELINES.md)
