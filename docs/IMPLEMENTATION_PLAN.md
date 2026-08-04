# HireFlow Implementation Plan

**Product:** HireFlow  
**Purpose:** Align product design with the real HR recruitment workflow before any application code is written.  
**Status:** Phase 0 documentation alignment **applied** (2026-08-04)  
**Constraint:** Documentation only at this stage — no application code yet.

This document analyzes the real business hiring process, proposes improvements, identifies gaps vs prior `/docs`, defines the entities the database must support, and sequences implementation. Source-of-truth docs listed in §9 have been updated to match.

---

## 0. Confirmed product constraints

| Constraint                  | Implication                                                                                               |
| --------------------------- | --------------------------------------------------------------------------------------------------------- |
| **MVP = one Recruiter**     | One authenticated user runs the full loop; Hiring Manager exists as a _process actor_, not a login (yet). |
| **No candidate accounts**   | Candidates never sign in. Status is recruiter-owned.                                                      |
| **Public application page** | Primary inbound path is a job-specific public apply form (no careers portal branding required for MVP).   |
| **Multi-tenant SaaS later** | Every business entity carries `tenant_id` from day one.                                                   |
| **Docs before code**        | Workflow and data model must be accepted before scaffolding apps.                                         |

These constraints **supersede** earlier PRD non-goals that deferred the public apply form. Public apply is now **MVP Must**.

---

## 1. Analysis of the real business workflow

### 1.1 Process as stated (15 steps)

|   # | Business step                                  | Process owner                   | System concept                                             |
| --: | ---------------------------------------------- | ------------------------------- | ---------------------------------------------------------- |
|   1 | Department requests a new employee             | Department / Hiring Manager     | **Requisition** (need) → becomes a Job in `draft`          |
|   2 | HR prepares or updates the Job Description     | Recruiter                       | Job content lifecycle (`draft`)                            |
|   3 | HR publishes the Job                           | Recruiter                       | Job status → `open` + public apply link                    |
|   4 | Candidates apply                               | Candidate (unauthenticated)     | Create/update **Candidate** + **Application** at `applied` |
|   5 | HR performs CV Filtering                       | Recruiter                       | Stage: `cv_screening`                                      |
|   6 | HR performs Phone Screening                    | Recruiter                       | Stage: `phone_screening`                                   |
|   7 | HR schedules interviews with Hiring Manager    | Recruiter                       | **Interview** records; stage: `interview`                  |
|   8 | Hiring Manager evaluates candidates            | Hiring Manager (offline in MVP) | **Interview feedback** entered by Recruiter on HM’s behalf |
|   9 | HR performs Reference Check                    | Recruiter                       | Stage: `reference_check`                                   |
|  10 | HR prepares Offer Letter                       | Recruiter                       | Stage: `offer` + **Offer** record                          |
|  11 | Candidate accepts                              | Candidate (offline)             | Offer status → `accepted`                                  |
|  12 | HR collects documents                          | Recruiter                       | Pre-hire **document checklist**                            |
|  13 | Candidate signs Job Description and Offer      | Candidate (offline)             | Signature / acknowledgment checklist items                 |
|  14 | Employee becomes Hired                         | Recruiter                       | Stage: `hired`; Job may become `filled`                    |
|  15 | HR sends Regret Letters to rejected candidates | Recruiter                       | **Communication** action + stage `rejected`                |

### 1.2 What this workflow gets right

1. **Demand before supply** — hiring starts with a department need, not a random job post.
2. **JD quality gate** — publish only after description is ready (`draft` → `open`).
3. **Screening is two skills** — CV filter ≠ phone screen; collapsing them loses operational truth.
4. **Recruiter owns coordination** — HM evaluates; HR schedules and drives the process (fits single-recruiter MVP).
5. **Hire is not “offer sent”** — references, documents, and signatures sit between commercial intent and employment.
6. **Rejection is a closing communication** — regret letters are part of professional process closure, not optional admin.

### 1.3 Friction / risk points in the as-is process

| Risk                                       | Why it matters                          | Product response                                                      |
| ------------------------------------------ | --------------------------------------- | --------------------------------------------------------------------- |
| Requisition forgotten after verbal request | Headcount drift                         | Persist request as draft job (or requisition) with requester metadata |
| Stages too coarse in spreadsheets          | “Where is this person?” becomes unclear | Fine-grained stages + immutable history                               |
| HM feedback lives in email/chat            | Decisions untraceable                   | Structured feedback fields even if Recruiter types them               |
| Offer acceptance informal                  | Disputes / rework                       | Explicit offer statuses                                               |
| Documents after accept are ad-hoc          | Delayed start dates                     | Checklist before `hired`                                              |
| Regret letters sent inconsistently         | Employer brand / legal optics           | Track “regret sent” per rejection                                     |

---

## 2. Suggested improvements

### 2.1 Adopt a clearer domain separation

Split the process into four lanes the UI should mirror:

```text
1. REQUISITION & JOB      → demand + JD + publish
2. ATTRACTION             → public apply + candidate intake
3. SELECTION              → CV → phone → interview → references
4. OFFER & PRE-HIRE       → offer → accept → documents/sign → hired
   (+ parallel: reject + regret letter at any selection/offer point)
```

### 2.2 Recommended default pipeline (aligned to real HR)

Replace the earlier coarse MVP stages with stages that map 1:1 to how HR actually works:

| Order | Stage key         | Display name               | Maps to business steps |
| ----: | ----------------- | -------------------------- | ---------------------- |
|     1 | `applied`         | Applied                    | 4                      |
|     2 | `cv_screening`    | CV Screening               | 5                      |
|     3 | `phone_screening` | Phone Screening            | 6                      |
|     4 | `interview`       | Interview                  | 7–8                    |
|     5 | `reference_check` | Reference Check            | 9                      |
|     6 | `offer`           | Offer                      | 10–11                  |
|     7 | `pre_hire`        | Pre-Hire / Onboarding Docs | 12–13                  |
|     8 | `hired`           | Hired                      | 14                     |
|     9 | `rejected`        | Rejected                   | 15 (terminal)          |
|    10 | `withdrawn`       | Withdrawn                  | Candidate-driven exit  |

**Notes:**

- `assessment` (take-home/test) remains **optional / later** — not in the stated real process; do not force it into MVP.
- Multiple HM interviews stay inside `interview` via multiple **Interview** records (do not invent a stage per interview round unless needed later).
- Terminal outcomes (`rejected`, `withdrawn`, `hired`) remain reachable from active stages with audit + reason codes.

### 2.3 Job lifecycle improvements

| Improvement        | Detail                                                                         |
| ------------------ | ------------------------------------------------------------------------------ |
| Explicit draft     | Step 1–2 live as Job `draft` (JD editable, not public).                        |
| Publish action     | Step 3 sets `open` and enables public apply token/link.                        |
| Requester metadata | Store requesting department + hiring manager name/email even without HM login. |
| Hold / close       | Keep `on_hold`, `closed`, `filled` for operational control.                    |

### 2.4 Offer & pre-hire improvements

Treat **Offer** as a first-class record (not only a stage label):

| Offer status | Meaning                                           |
| ------------ | ------------------------------------------------- |
| `draft`      | Letter being prepared                             |
| `sent`       | Extended to candidate                             |
| `accepted`   | Candidate accepted                                |
| `declined`   | Candidate declined → usually reject/withdraw path |
| `rescinded`  | Company withdrew offer                            |
| `expired`    | Optional later                                    |

After `accepted`, move application to `pre_hire` and complete a checklist before `hired`:

- Identity / right-to-work docs (tenant-configurable later; MVP: free-form checklist)
- Signed Offer acknowledgment
- Signed Job Description acknowledgment
- Any other recruiter-defined items

### 2.5 Communications improvements

| Improvement                | Detail                                                                                    |
| -------------------------- | ----------------------------------------------------------------------------------------- |
| Regret letter is an action | Not a pipeline stage. On reject (or after hire fills role), Recruiter marks/sends regret. |
| MVP delivery mode          | Manual “mark as sent” + optional template copy is enough; automated email can follow.     |
| Always log                 | Who sent, when, which template/reason — supports consistency and audit.                   |

### 2.6 Single-recruiter MVP pattern for HM evaluation

Do **not** block MVP on Hiring Manager accounts.

- Job stores `hiring_manager_name` / `hiring_manager_email` (and optional notes).
- Interview type includes `hiring_manager`.
- Recruiter enters HM evaluation into `interview_feedback` (attribution note: “on behalf of HM”).
- Phase 2: invite HM user, assign to job, HM submits feedback directly.

### 2.7 Public apply improvements (no candidate account)

| Rule         | Detail                                                                             |
| ------------ | ---------------------------------------------------------------------------------- |
| Apply link   | Per-job public URL: `/apply/{public_token}` or `/apply/{tenantSlug}/{jobSlug}`     |
| Creates      | Candidate (dedupe by email within tenant) + Application at `applied` + resume file |
| No login     | Candidate cannot view status; confirmation message only                            |
| Spam / abuse | Rate limit, honeypot, file type/size limits; CAPTCHA later if needed               |
| Closed jobs  | Apply form returns “no longer accepting applications”                              |

---

## 3. Missing steps (vs real-world HR completeness)

Items below are **not all MVP**. They are called out so the model does not paint us into a corner.

### 3.1 Missing or underspecified in the stated 15 steps

| Gap                                               | Recommendation                                                             | MVP?                               |
| ------------------------------------------------- | -------------------------------------------------------------------------- | ---------------------------------- |
| **Budget / headcount approval** before JD publish | Optional Job field `approval_status` or note; full approval workflow later | Should (simple field) / full Later |
| **Internal vs external** candidate                | `candidate_type` or application flag                                       | Should                             |
| **Sourcing beyond apply**                         | Keep manual candidate add for referrals/agencies                           | Must                               |
| **Duplicate applications**                        | One active application per candidate+job; show existing if re-apply        | Must                               |
| **Interview no-show / cancel**                    | Interview statuses already planned                                         | Must                               |
| **Background check** (distinct from references)   | Optional checklist item or later stage                                     | Later (region-dependent)           |
| **Medical / fitness checks**                      | Checklist item where legally required                                      | Later                              |
| **Offer expiry date**                             | Field on Offer                                                             | Should                             |
| **Start date & employee ID handoff**              | On hire: `start_date`; HRIS export later                                   | Must (`start_date`)                |
| **Candidate withdrawal**                          | Stage `withdrawn` + note                                                   | Must                               |
| **Role filled → bulk reject remaining**           | Recruiter action: reject others + regret letters                           | Should                             |
| **GDPR consent on apply**                         | Consent checkbox + timestamp on application                                | Must (EU-ready)                    |
| **Data retention / purge**                        | Design now; tooling later                                                  | Design Must / tooling Later        |

### 3.2 Gaps vs current HireFlow docs (must reconcile)

| Current docs say                                                     | Real process / new constraint            | Action                                        |
| -------------------------------------------------------------------- | ---------------------------------------- | --------------------------------------------- |
| Public apply is out of MVP / Phase 1.5                               | Public apply is MVP Must                 | Update PRD + Roadmap                          |
| Stages: applied → screening → interview → assessment → offer → hired | Need CV, phone, references, pre-hire     | Update RECRUITMENT_WORKFLOW                   |
| Offer is mostly a stage label                                        | Need Offer entity + statuses             | Update DATABASE_DESIGN                        |
| Documents only as resume files                                       | Need pre-hire docs + signature checklist | Add entities                                  |
| Regret letters not modeled                                           | Required closing step                    | Add communications model                      |
| Department request not modeled                                       | Step 1 is the start of demand            | Capture as draft job + requester fields (MVP) |
| Manual candidate entry primary                                       | Apply form primary; manual still needed  | Flip priority in PRD                          |

---

## 4. End-to-end target workflow (system view)

```text
Department need
    │
    ▼
[Job: draft]  JD prepared · requester + HM recorded
    │ publish
    ▼
[Job: open] ── public apply link live
    │
    ▼
Candidate submits apply form (no account)
    │
    ▼
Application: applied
    │
    ▼
cv_screening ──reject──► rejected ──► regret letter (logged)
    │
    ▼
phone_screening ──reject──► rejected ──► regret letter
    │
    ▼
interview (1..N interviews + HM feedback) ──reject──► rejected
    │
    ▼
reference_check ──reject──► rejected
    │
    ▼
offer (draft → sent → accepted | declined)
    │ accepted
    ▼
pre_hire (documents + signed JD + signed offer)
    │
    ▼
hired  ──► optionally mark Job filled
             ──► reject remaining candidates + regret letters

Candidate may withdraw at any active stage → withdrawn
```

---

## 5. Entities required in the database

### 5.1 Already planned (keep; adjust fields)

| Entity                     | Role in real workflow                      |
| -------------------------- | ------------------------------------------ |
| `tenants`                  | Company (SaaS customer)                    |
| `users`                    | Recruiter login identity                   |
| `tenant_memberships`       | User↔tenant + role                         |
| `jobs`                     | Requisition/JD/publish lifecycle           |
| `candidates`               | Person record (no login)                   |
| `applications`             | Candidacy + `current_stage`                |
| `application_stage_events` | Immutable stage history                    |
| `pipeline_stages`          | Tenant stage catalog (seed new keys)       |
| `interviews`               | Scheduled HM/other interviews              |
| `interview_feedback`       | HM evaluation captured by Recruiter in MVP |
| `files`                    | Resumes + later pre-hire attachments       |
| `audit_events`             | Security/admin audit                       |

### 5.2 Required additions / upgrades for the real process

#### A. Job / requisition fields (on `jobs` for MVP — avoid separate table initially)

| Field                   | Purpose                                   |
| ----------------------- | ----------------------------------------- |
| `requesting_department` | Step 1                                    |
| `hiring_manager_name`   | Steps 7–8 (no HM user yet)                |
| `hiring_manager_email`  | Contact / future invite                   |
| `requested_by_name`     | Who requested the headcount               |
| `requested_at`          | When need was raised                      |
| `published_at`          | When moved to `open`                      |
| `public_apply_token`    | Opaque token for public form              |
| `apply_enabled`         | Boolean; false when closed/filled/on_hold |

> **Later:** split `job_requisitions` if approval chains become real. MVP: one `jobs` row from request through fill is enough.

#### B. `offers` (new — first-class)

| Column (logical)                           | Notes                                                           |
| ------------------------------------------ | --------------------------------------------------------------- |
| `id`, `tenant_id`, `application_id`        | One active offer per application (MVP)                          |
| `status`                                   | `draft`, `sent`, `accepted`, `declined`, `rescinded`, `expired` |
| `compensation_summary`                     | Free text MVP                                                   |
| `currency` / `base_salary`                 | Optional structured fields                                      |
| `offer_date`, `expiry_date`, `accepted_at` | Dates                                                           |
| `start_date_proposed`                      |                                                                 |
| `letter_file_id`                           | FK → `files` (generated/uploaded PDF)                           |
| `created_by`, timestamps                   |                                                                 |

#### C. `application_checklist_items` (new — pre-hire / docs / signatures)

| Column (logical)                    | Notes                                                 |
| ----------------------------------- | ----------------------------------------------------- |
| `id`, `tenant_id`, `application_id` |                                                       |
| `key`                               | e.g. `signed_offer`, `signed_jd`, `id_document`       |
| `label`                             | Display                                               |
| `item_type`                         | `document_upload`, `acknowledgment`, `manual_confirm` |
| `status`                            | `pending`, `completed`, `waived`                      |
| `file_id`                           | Optional                                              |
| `completed_at`, `completed_by`      | Recruiter confirms in MVP                             |
| `sort_order`                        |                                                       |

Seed default checklist when entering `pre_hire` (or on offer accept).

#### D. `communications` (new — regret letters and future emails)

| Column (logical)                    | Notes                                      |
| ----------------------------------- | ------------------------------------------ |
| `id`, `tenant_id`, `application_id` |                                            |
| `type`                              | `regret_letter`, `offer_letter`, `general` |
| `channel`                           | `email_manual`, `email_system`, `other`    |
| `status`                            | `draft`, `sent`, `failed`                  |
| `template_key`                      | Optional                                   |
| `subject`, `body`                   | Optional snapshot                          |
| `sent_at`, `sent_by`                |                                            |
| `metadata`                          | JSONB                                      |

MVP: Recruiter can “Log regret letter sent” without SMTP. System email is Phase 2+.

#### E. Public apply support fields

On `applications` (or related):

| Field                  | Purpose                                   |
| ---------------------- | ----------------------------------------- |
| `source`               | Prefer `inbound_apply` vs referral/manual |
| `consent_at`           | GDPR/privacy consent timestamp            |
| `consent_text_version` | Which notice was accepted                 |
| `submitted_via`        | `public_form`, `manual`, `import`         |

On `candidates`: keep dedupe `UNIQUE (tenant_id, email)`.

#### F. Reference check (MVP approach)

**Option chosen for MVP:** stage `reference_check` + notes on application / stage event.  
**Optional light table (Should):**

`reference_checks`: contact name, relationship, phone/email, outcome (`positive`/`neutral`/`negative`), notes, checked_at, checked_by.

Prefer the light table if references are frequently multi-contact; otherwise stage notes suffice for v1.

### 5.3 Entity relationship (updated)

```text
tenants
  ├── tenant_memberships ── users
  ├── pipeline_stages
  ├── jobs
  │     └── applications ── candidates
  │           ├── application_stage_events
  │           ├── interviews
  │           │     └── interview_feedback
  │           ├── offers
  │           ├── application_checklist_items
  │           ├── communications
  │           └── reference_checks (optional)
  ├── files
  └── audit_events
```

### 5.4 Stage catalog seed (per tenant)

```text
applied
cv_screening
phone_screening
interview
reference_check
offer
pre_hire
hired          (terminal_success)
rejected       (terminal_closed)
withdrawn      (terminal_closed)
```

---

## 6. MVP scope lock (what we will build first)

### 6.1 In scope (Recruiter-only MVP)

1. Auth for one Recruiter inside one Tenant (multi-tenant schema ready).
2. Jobs: request metadata → draft JD → publish → open/hold/close/fill.
3. Public apply page (no candidate account) + resume upload.
4. Manual candidate/application entry (referrals).
5. Pipeline board/list with stages listed in §2.2.
6. Interviews + feedback (Recruiter enters HM feedback).
7. Offer record + accept/decline.
8. Pre-hire checklist (docs + signed JD/offer confirmations).
9. Hire outcome + start date.
10. Reject with reason + log regret letter.
11. Stage history audit trail.
12. Basic search/filter and simple dashboard.

### 6.2 Explicitly out of MVP

- Hiring Manager / Interviewer logins
- Automated SMTP regret/offer emails (logging only is enough)
- Full e-signature provider (DocuSign etc.) — Recruiter confirms signatures manually
- Careers portal / company branding site
- AI CV ranking
- Payroll / HRIS sync
- Custom per-tenant stages UI (seed defaults; customization later)
- Billing

### 6.3 MVP acceptance scenario (business)

A Recruiter can:

1. Create a draft job from a department request (with HM contact).
2. Publish and open a public apply link.
3. Receive an application from the public form (candidate has no account).
4. Move candidate: CV → Phone → Interview (with feedback) → References → Offer.
5. Mark offer accepted; complete pre-hire checklist; mark Hired.
6. Reject another candidate; log that a regret letter was sent.
7. See full stage history for both applications.

---

## 7. Phased implementation plan

### Phase 0 — Documentation alignment

| Task                                                             | Output               | Status                    |
| ---------------------------------------------------------------- | -------------------- | ------------------------- |
| Accept this IMPLEMENTATION_PLAN                                  | Stakeholder sign-off | Applied to docs           |
| Update RECRUITMENT_WORKFLOW.md to new stages + rules             | Workflow SoT         | Done                      |
| Update DATABASE_DESIGN.md with new entities/fields               | Data SoT             | Done                      |
| Update PRODUCT_REQUIREMENTS.md (public apply Must; HM offline)   | PRD SoT              | Done                      |
| Update USER_ROLES.md / UI_GUIDELINES.md / SYSTEM_ARCHITECTURE.md | Cross-doc SoT        | Done                      |
| Update ROADMAP.md phase mapping                                  | Delivery SoT         | Done                      |
| Record stack decisions (web/API/auth/ORM)                        | Decision log         | Open — confirm at kickoff |

**Exit:** Docs consistent with real HR process; no code yet. **Met for documentation.**

### Phase 1 — Platform skeleton

- Monorepo apps: `apps/web`, `apps/api`
- PostgreSQL + migrations for core tenancy tables
- Recruiter auth (email/password sessions)
- Tenant provisioning seeds default `pipeline_stages`
- Docker Compose for local Postgres (+ MinIO/S3-compatible for files)
- Health checks + CI placeholders
- Automated test: cross-tenant access denied

**Exit:** Recruiter can sign in to empty shell for a provisioned tenant.

### Phase 2 — Jobs & public apply

- Jobs CRUD + statuses (`draft` → `open` → …)
- Public apply token + unauthenticated apply API
- Candidate dedupe by email
- Resume upload to object storage
- Consent capture

**Exit:** Public candidate can apply to an open job; Recruiter sees application in `applied`.

### Phase 3 — Selection pipeline

- Board + list views
- Transitions with validation + `application_stage_events`
- CV / phone screening movements
- Interviews + feedback
- Reference check stage (+ optional `reference_checks` table)
- Reject + reason codes

**Exit:** Full selection loop works for one job with multiple candidates.

### Phase 4 — Offer, pre-hire, hire, regret

- `offers` CRUD + statuses
- Move to `pre_hire` on accept
- Checklist items + file attachments
- Transition to `hired`; job fill prompt
- `communications` log for regret letters
- Bulk “reject remaining” helper (Should)

**Exit:** Business acceptance scenario in §6.3 passes.

### Phase 5 — Multi-user collaboration (post-MVP)

- Invite Hiring Manager / Interviewers
- Job assignments
- HM submits own feedback
- Permission matrix enforcement

### Phase 6 — SaaS hardening

- Self-serve tenant signup
- Billing, monitoring, backups
- RLS evaluation
- Automated email delivery

### Phase 7 — Workflow power-ups & integrations

- Custom stages, e-sign, calendar sync, analytics, AI assists

---

## 8. Suggested technical decisions (confirm at kickoff)

| Topic | Recommendation                          | Why                                              |
| ----- | --------------------------------------- | ------------------------------------------------ |
| Web   | Next.js (App Router) + TypeScript       | SSR for public apply page; solid React DX        |
| API   | NestJS or Fastify modular monolith      | Clear domain modules; one language               |
| DB    | PostgreSQL + Prisma or Drizzle          | Migrations + tenant-scoped queries               |
| Auth  | First-party sessions (HTTP-only cookie) | Simple for one Recruiter; no vendor lock for MVP |
| Files | S3-compatible (MinIO local)             | Resumes + offer PDFs                             |
| Email | Log-only in MVP                         | Avoid SMTP complexity until templates stabilize  |

Open decisions should be written into ROADMAP.md decision log when chosen.

---

## 9. Documentation update checklist (before coding)

- [x] `RECRUITMENT_WORKFLOW.md` — replace stage model with §2.2; add offer/pre-hire/regret rules
- [x] `DATABASE_DESIGN.md` — add offers, checklist items, communications, job public-apply fields
- [x] `PRODUCT_REQUIREMENTS.md` — public apply Must; remove contradicting non-goals; revise acceptance criteria
- [x] `USER_ROLES.md` — clarify HM is offline actor in MVP; Recruiter enters feedback
- [x] `ROADMAP.md` — remap phases to §7; mark public apply in MVP
- [x] `UI_GUIDELINES.md` — public apply page + recruiter pipeline IA
- [x] `README.md` — point to this plan; note Phase 0 alignment complete
- [x] `SYSTEM_ARCHITECTURE.md` — public apply surface + domain modules

---

## 10. Risks specific to this workflow

| Risk                                    | Mitigation                                                       |
| --------------------------------------- | ---------------------------------------------------------------- |
| Over-modeling pre-hire into a full HRIS | Checklist + files only; no payroll entities                      |
| Building HM portals too early           | Free-text HM + recruiter-entered feedback                        |
| Public apply spam                       | Rate limits, file constraints, tokenized URLs                    |
| Stage proliferation confusion           | Stable keys; clear board columns; skip-forward allowed with note |
| E-sign scope creep                      | Manual acknowledgment flags in MVP                               |
| Doc drift                               | This plan + SoT docs updated before code                         |

---

## 11. Immediate next actions

1. Confirm stack from §8 (web/API/auth/ORM) and remaining PRD open questions (cloud).
2. Begin **Phase 1** scaffolding in `apps/*` and `packages/database`.
3. Keep `/docs` updated when decisions change; docs remain the contract.

---

## 12. Related documents

- [PRODUCT_REQUIREMENTS.md](./PRODUCT_REQUIREMENTS.md)
- [RECRUITMENT_WORKFLOW.md](./RECRUITMENT_WORKFLOW.md)
- [DATABASE_DESIGN.md](./DATABASE_DESIGN.md)
- [USER_ROLES.md](./USER_ROLES.md)
- [SYSTEM_ARCHITECTURE.md](./SYSTEM_ARCHITECTURE.md)
- [UI_GUIDELINES.md](./UI_GUIDELINES.md)
- [ROADMAP.md](./ROADMAP.md)
