# Database Design

**Product:** HireFlow  
**Purpose:** Logical data model for a multi-tenant ATS  
**Status:** Baseline (source of truth) — aligned with IMPLEMENTATION_PLAN.md (2026-08-04)  
**Engine assumption:** PostgreSQL

This document defines entities, relationships, constraints, and tenancy rules. Physical migrations will follow this design when application development begins.

---

## 1. Design principles

1. **Tenant everywhere** — business tables include `tenant_id` (UUID) with composite uniqueness where needed.
2. **Application-centric pipeline** — stage state belongs to `applications`, not `candidates`.
3. **Append-only history** — stage changes and critical decisions are immutable events.
4. **Soft deletes where history matters** — prefer `archived_at` / `deleted_at` over hard deletes for jobs/candidates.
5. **Referential integrity** — foreign keys enforced in Postgres.
6. **Stable enumerations** — store stage/status keys as text (or enums) aligned with workflow docs.
7. **No candidate accounts** — candidates are data records only; auth tables are for tenant users (Recruiter).
8. **Offer & communications are first-class** — not only free-text notes on the application.

---

## 2. Entity-relationship overview

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
  │           └── reference_checks
  ├── files
  └── audit_events
```

---

## 3. Core tables

### 3.1 `tenants`

| Column       | Type          | Notes                           |
| ------------ | ------------- | ------------------------------- |
| `id`         | UUID PK       |                                 |
| `name`       | TEXT NOT NULL | Company display name            |
| `slug`       | TEXT UNIQUE   | URL-safe identifier             |
| `timezone`   | TEXT          | Default `UTC`                   |
| `locale`     | TEXT          | Default `en-US`                 |
| `status`     | TEXT          | `active`, `suspended`, `closed` |
| `created_at` | TIMESTAMPTZ   |                                 |
| `updated_at` | TIMESTAMPTZ   |                                 |

### 3.2 `users`

| Column          | Type          | Notes                       |
| --------------- | ------------- | --------------------------- |
| `id`            | UUID PK       |                             |
| `email`         | CITEXT UNIQUE | Global unique for MVP login |
| `password_hash` | TEXT          | Nullable if SSO later       |
| `full_name`     | TEXT          |                             |
| `status`        | TEXT          | `active`, `disabled`        |
| `created_at`    | TIMESTAMPTZ   |                             |
| `updated_at`    | TIMESTAMPTZ   |                             |

> Candidates are **not** users. Only tenant staff authenticate.

### 3.3 `tenant_memberships`

| Column       | Type              | Notes                          |
| ------------ | ----------------- | ------------------------------ |
| `id`         | UUID PK           |                                |
| `tenant_id`  | UUID FK → tenants |                                |
| `user_id`    | UUID FK → users   |                                |
| `role`       | TEXT NOT NULL     | See USER_ROLES.md              |
| `status`     | TEXT              | `active`, `invited`, `revoked` |
| `created_at` | TIMESTAMPTZ       |                                |
| `updated_at` | TIMESTAMPTZ       |                                |

**Constraints:** `UNIQUE (tenant_id, user_id)`

### 3.4 `jobs`

| Column                  | Type             | Notes                                                 |
| ----------------------- | ---------------- | ----------------------------------------------------- |
| `id`                    | UUID PK          |                                                       |
| `tenant_id`             | UUID FK          |                                                       |
| `title`                 | TEXT NOT NULL    |                                                       |
| `department`            | TEXT             | Display department (may mirror requesting_department) |
| `location`              | TEXT             |                                                       |
| `employment_type`       | TEXT             | `full_time`, `part_time`, `contract`, `intern`        |
| `description`           | TEXT             | Job description (Markdown/plain)                      |
| `status`                | TEXT             | `draft`, `open`, `on_hold`, `closed`, `filled`        |
| `openings`              | INT              | Default 1                                             |
| `requesting_department` | TEXT             | Step 1 — department that requested headcount          |
| `requested_by_name`     | TEXT             | Who raised the request                                |
| `requested_at`          | TIMESTAMPTZ      | When need was raised                                  |
| `hiring_manager_name`   | TEXT             | HM process actor (no login in MVP)                    |
| `hiring_manager_email`  | TEXT             | Contact / future invite                               |
| `published_at`          | TIMESTAMPTZ NULL | Set when first published to `open`                    |
| `public_apply_token`    | TEXT UNIQUE      | Opaque token for public apply URL                     |
| `apply_enabled`         | BOOLEAN          | Default false until published                         |
| `created_by`            | UUID FK → users  |                                                       |
| `archived_at`           | TIMESTAMPTZ NULL |                                                       |
| `created_at`            | TIMESTAMPTZ      |                                                       |
| `updated_at`            | TIMESTAMPTZ      |                                                       |

**Indexes:** `(tenant_id, status)`, `(tenant_id, created_at DESC)`, unique `public_apply_token`

> MVP keeps requisition metadata on `jobs` (no separate `job_requisitions` table). Split later if approval chains require it.

### 3.5 `candidates`

| Column         | Type                 | Notes                                                          |
| -------------- | -------------------- | -------------------------------------------------------------- |
| `id`           | UUID PK              |                                                                |
| `tenant_id`    | UUID FK              |                                                                |
| `full_name`    | TEXT NOT NULL        |                                                                |
| `email`        | CITEXT               |                                                                |
| `phone`        | TEXT                 |                                                                |
| `source`       | TEXT                 | `inbound`, `referral`, `linkedin`, `agency`, `manual`, `other` |
| `linkedin_url` | TEXT                 |                                                                |
| `notes`        | TEXT                 | Recruiter notes                                                |
| `created_by`   | UUID FK → users NULL | Null when created via public apply                             |
| `archived_at`  | TIMESTAMPTZ NULL     |                                                                |
| `created_at`   | TIMESTAMPTZ          |                                                                |
| `updated_at`   | TIMESTAMPTZ          |                                                                |

**Constraints / indexes:**

- `UNIQUE (tenant_id, email)` where email is not null (duplicate detection)
- Index `(tenant_id, full_name)`

### 3.6 `applications`

The central pipeline record.

| Column                 | Type                 | Notes                                              |
| ---------------------- | -------------------- | -------------------------------------------------- |
| `id`                   | UUID PK              |                                                    |
| `tenant_id`            | UUID FK              |                                                    |
| `job_id`               | UUID FK → jobs       |                                                    |
| `candidate_id`         | UUID FK → candidates |                                                    |
| `current_job_stage_id` | UUID FK → job_stages | Pipeline position source of truth (same job)       |
| `status`               | TEXT NOT NULL        | Lifecycle state (not derived from stage names)       |
| `reject_reason_code`   | TEXT NULL            | Required when rejected                             |
| `hired_at`             | TIMESTAMPTZ NULL     |                                                    |
| `start_date`           | DATE NULL            |                                                    |
| `withdrawn_at`         | TIMESTAMPTZ NULL     |                                                    |
| `rejected_at`          | TIMESTAMPTZ NULL     |                                                    |
| `source`               | TEXT                 | `inbound_apply`, `referral`, `manual`, `import`, … |
| `submitted_via`        | TEXT                 | `public_form`, `manual`, `import`                  |
| `consent_at`           | TIMESTAMPTZ NULL     | GDPR/privacy consent                               |
| `consent_text_version` | TEXT NULL            | Which notice was accepted                          |
| `created_by`           | UUID FK → users NULL | Null for public apply                              |
| `created_at`           | TIMESTAMPTZ          |                                                    |
| `updated_at`           | TIMESTAMPTZ          |                                                    |

**Lifecycle vs pipeline stage:**

- `status` is **application lifecycle state**: `active`, `hired`, `disqualified`, `withdrawn`, `transferred`.
- Pipeline position is **only** `current_job_stage_id` → `job_stages` for the same `job_id`.
- Do **not** derive lifecycle state from arbitrary stage names.
- New applications are created in the job’s designated **Applied entry stage** (`job_stages.is_applied_entry`), not “first by sort order” and not generic intake.

**Constraints:**

- Partial unique: at most one row with `status = 'active'` per `(tenant_id, job_id, candidate_id)` — historical (non-active) applications for the same pair are allowed
- Identity fields `tenant_id`, `candidate_id`, and `job_id` are **immutable after insert** (trigger-enforced). Moving a candidacy to another job creates a new application row in a later step — never rewrite `job_id`
- Composite FK: `(current_job_stage_id, job_id) → job_stages(id, job_id)`
- `current_job_stage_id` changes only via `transition_application_stage` (guard trigger)
- FK integrity: job and candidate must share same `tenant_id`

**Indexes:** `(tenant_id, job_id, current_job_stage_id)`, `(tenant_id, candidate_id)`, partial unique on active `(tenant_id, job_id, candidate_id)`

### 3.7 `application_stage_events`

Append-only transition log with immutable stage snapshots.

| Column               | Type                   | Notes                                              |
| -------------------- | ---------------------- | -------------------------------------------------- |
| `id`                 | UUID PK                |                                                    |
| `tenant_id`          | UUID FK                |                                                    |
| `application_id`     | UUID FK → applications |                                                    |
| `job_id`             | UUID FK → jobs         | Same job as application; enables composite stage FK |
| `event_type`         | TEXT NOT NULL          | `initial`, `transition`, `migration_backfill`      |
| `from_job_stage_id`  | UUID NULL              | Soft live ref; `ON DELETE SET NULL`                |
| `to_job_stage_id`    | UUID NULL              | Soft live ref; `ON DELETE SET NULL`                |
| `from_stage_key`     | TEXT NULL              | Snapshot (null on initial)                         |
| `from_stage_name`    | TEXT NULL              | Snapshot                                           |
| `from_stage_category`| TEXT NULL              | Snapshot                                           |
| `to_stage_key`       | TEXT NOT NULL          | Snapshot                                           |
| `to_stage_name`      | TEXT NOT NULL          | Snapshot                                           |
| `to_stage_category`  | TEXT NOT NULL          | Snapshot                                           |
| `actor_user_id`      | UUID FK → users NULL   | Null for public-form initial event                 |
| `note`               | TEXT                   |                                                    |
| `reason_code`        | TEXT                   | Especially for rejects                             |
| `occurred_at`        | TIMESTAMPTZ NOT NULL   | When **this event** occurred (History Never Lies)  |
| `metadata`           | JSONB                  | e.g. `application_created_at` on migration_backfill |

**Indexes:** `(application_id, occurred_at)`, `(tenant_id, occurred_at DESC)`  
**Rule:** no updates/deletes (append-only trigger). Timeline UI must read snapshot columns, not live `job_stages.name`.

### 3.8 `job_stages` (job pipeline snapshot)

Per-job stages copied from a pipeline template at sync/publish time.

| Column             | Type          | Notes                                              |
| ------------------ | ------------- | -------------------------------------------------- |
| `id`               | UUID PK       |                                                    |
| `tenant_id`        | UUID FK       |                                                    |
| `job_id`           | UUID FK       |                                                    |
| `key`              | TEXT NOT NULL | Stable key                                         |
| `name`             | TEXT NOT NULL | Display label                                      |
| `sort_order`       | INT NOT NULL  |                                                    |
| `color`            | TEXT          | Hex                                                |
| `sla_days`         | INT NULL      |                                                    |
| `category`         | TEXT NOT NULL | intake/screening/…/hired/closed/custom             |
| `notes`            | TEXT NULL     |                                                    |
| `is_applied_entry` | BOOLEAN       | Exactly one true per job (partial unique)          |

**Constraints:** `UNIQUE (job_id, key)`, `UNIQUE (id, job_id)` (composite FK target), exactly one `is_applied_entry` per job.

Public/manual apply always enters the Applied entry stage. Applied ≠ Review; Review is a later manual transition.

### 3.8b `pipeline_stages` (legacy tenant catalog)

Tenant-configurable stage catalog (seeded with defaults; templates are preferred for new jobs).

| Column       | Type          | Notes                                           |
| ------------ | ------------- | ----------------------------------------------- |
| `id`         | UUID PK       |                                                 |
| `tenant_id`  | UUID FK       |                                                 |
| `key`        | TEXT NOT NULL | Stable key (`cv_screening`)                     |
| `name`       | TEXT NOT NULL | Display label                                   |
| `sort_order` | INT NOT NULL  |                                                 |
| `stage_type` | TEXT          | `active`, `terminal_success`, `terminal_closed` |
| `is_active`  | BOOLEAN       | Soft-disable without deleting history           |
| `created_at` | TIMESTAMPTZ   |                                                 |

**Constraints:** `UNIQUE (tenant_id, key)`, carefully managed `sort_order` uniqueness per tenant

**Default seed keys (per new tenant):**  
`applied`, `cv_screening`, `phone_screening`, `interview`, `reference_check`, `offer`, `pre_hire`, `hired`, `rejected`, `withdrawn`

### 3.9 `interviews`

| Column                | Type                   | Notes                                           |
| --------------------- | ---------------------- | ----------------------------------------------- |
| `id`                  | UUID PK                |                                                 |
| `tenant_id`           | UUID FK                |                                                 |
| `application_id`      | UUID FK → applications |                                                 |
| `interview_type`      | TEXT                   | See workflow doc                                |
| `status`              | TEXT                   | `scheduled`, `completed`, `canceled`, `no_show` |
| `scheduled_starts_at` | TIMESTAMPTZ            |                                                 |
| `scheduled_ends_at`   | TIMESTAMPTZ            |                                                 |
| `interviewer_name`    | TEXT                   | MVP free text (often HM name)                   |
| `interviewer_email`   | TEXT                   | MVP free text                                   |
| `interviewer_user_id` | UUID NULL              | Phase: multi-user when HM logs in               |
| `location_or_link`    | TEXT                   |                                                 |
| `created_by`          | UUID FK → users        |                                                 |
| `created_at`          | TIMESTAMPTZ            |                                                 |
| `updated_at`          | TIMESTAMPTZ            |                                                 |

**Indexes:** `(tenant_id, scheduled_starts_at)`, `(application_id)`

### 3.10 `interview_feedback`

| Column              | Type                 | Notes                       |
| ------------------- | -------------------- | --------------------------- |
| `id`                | UUID PK              |                             |
| `tenant_id`         | UUID FK              |                             |
| `interview_id`      | UUID FK → interviews |                             |
| `author_user_id`    | UUID FK → users      | Recruiter in MVP            |
| `on_behalf_of_name` | TEXT NULL            | HM name when entered for HM |
| `recommendation`    | TEXT                 | `strong_yes` … `strong_no`  |
| `score`             | INT NULL             | 1–5 check constraint        |
| `notes`             | TEXT NOT NULL        |                             |
| `created_at`        | TIMESTAMPTZ          |                             |
| `updated_at`        | TIMESTAMPTZ          |                             |

**Constraints:** `UNIQUE (interview_id, author_user_id)` for MVP (one feedback per author per interview)

### 3.11 `offers`

| Column                 | Type                   | Notes                                                           |
| ---------------------- | ---------------------- | --------------------------------------------------------------- |
| `id`                   | UUID PK                |                                                                 |
| `tenant_id`            | UUID FK                |                                                                 |
| `application_id`       | UUID FK → applications |                                                                 |
| `status`               | TEXT                   | `draft`, `sent`, `accepted`, `declined`, `rescinded`, `expired` |
| `compensation_summary` | TEXT                   | Free text MVP                                                   |
| `currency`             | TEXT NULL              |                                                                 |
| `base_salary`          | NUMERIC NULL           | Optional structured                                             |
| `offer_date`           | DATE NULL              |                                                                 |
| `expiry_date`          | DATE NULL              |                                                                 |
| `accepted_at`          | TIMESTAMPTZ NULL       |                                                                 |
| `start_date_proposed`  | DATE NULL              |                                                                 |
| `letter_file_id`       | UUID NULL FK → files   | Uploaded/generated offer PDF                                    |
| `created_by`           | UUID FK → users        |                                                                 |
| `created_at`           | TIMESTAMPTZ            |                                                                 |
| `updated_at`           | TIMESTAMPTZ            |                                                                 |

**Constraints (MVP):** at most one **active** offer per application (enforce in app; or partial unique index where status not in terminal declined/rescinded/expired — start with app rule + latest-row query).

**Indexes:** `(application_id)`, `(tenant_id, status)`

### 3.12 `application_checklist_items`

Pre-hire documents and acknowledgments.

| Column           | Type                   | Notes                                                 |
| ---------------- | ---------------------- | ----------------------------------------------------- |
| `id`             | UUID PK                |                                                       |
| `tenant_id`      | UUID FK                |                                                       |
| `application_id` | UUID FK → applications |                                                       |
| `key`            | TEXT NOT NULL          | e.g. `signed_offer`, `signed_jd`, `id_document`       |
| `label`          | TEXT NOT NULL          | Display                                               |
| `item_type`      | TEXT                   | `document_upload`, `acknowledgment`, `manual_confirm` |
| `status`         | TEXT                   | `pending`, `completed`, `waived`                      |
| `file_id`        | UUID NULL FK → files   |                                                       |
| `completed_at`   | TIMESTAMPTZ NULL       |                                                       |
| `completed_by`   | UUID FK → users NULL   | Recruiter confirms in MVP                             |
| `sort_order`     | INT                    |                                                       |
| `created_at`     | TIMESTAMPTZ            |                                                       |
| `updated_at`     | TIMESTAMPTZ            |                                                       |

**Constraints:** `UNIQUE (application_id, key)`  
**Seed:** when application enters `pre_hire`, insert default items (see RECRUITMENT_WORKFLOW.md).

### 3.13 `communications`

Outbound message log (regret letters, later system email).

| Column           | Type                   | Notes                                      |
| ---------------- | ---------------------- | ------------------------------------------ |
| `id`             | UUID PK                |                                            |
| `tenant_id`      | UUID FK                |                                            |
| `application_id` | UUID FK → applications |                                            |
| `type`           | TEXT                   | `regret_letter`, `offer_letter`, `general` |
| `channel`        | TEXT                   | `email_manual`, `email_system`, `other`    |
| `status`         | TEXT                   | `draft`, `sent`, `failed`                  |
| `template_key`   | TEXT NULL              |                                            |
| `subject`        | TEXT NULL              |                                            |
| `body`           | TEXT NULL              | Optional snapshot                          |
| `sent_at`        | TIMESTAMPTZ NULL       |                                            |
| `sent_by`        | UUID FK → users NULL   |                                            |
| `metadata`       | JSONB                  | Non-sensitive context                      |
| `created_at`     | TIMESTAMPTZ            |                                            |
| `updated_at`     | TIMESTAMPTZ            |                                            |

**Indexes:** `(application_id, type)`, `(tenant_id, sent_at DESC)`

### 3.14 `reference_checks`

| Column           | Type                   | Notes                                                |
| ---------------- | ---------------------- | ---------------------------------------------------- |
| `id`             | UUID PK                |                                                      |
| `tenant_id`      | UUID FK                |                                                      |
| `application_id` | UUID FK → applications |                                                      |
| `contact_name`   | TEXT NOT NULL          |                                                      |
| `relationship`   | TEXT                   | e.g. former manager                                  |
| `email`          | TEXT                   |                                                      |
| `phone`          | TEXT                   |                                                      |
| `outcome`        | TEXT                   | `positive`, `neutral`, `negative`, `unable_to_reach` |
| `notes`          | TEXT                   |                                                      |
| `checked_at`     | TIMESTAMPTZ            |                                                      |
| `checked_by`     | UUID FK → users        |                                                      |
| `created_at`     | TIMESTAMPTZ            |                                                      |
| `updated_at`     | TIMESTAMPTZ            |                                                      |

**Indexes:** `(application_id)`

### 3.15 `files`

| Column         | Type                 | Notes                                                 |
| -------------- | -------------------- | ----------------------------------------------------- |
| `id`           | UUID PK              |                                                       |
| `tenant_id`    | UUID FK              |                                                       |
| `owner_type`   | TEXT                 | `candidate`, `application`, `offer`, `checklist_item` |
| `owner_id`     | UUID                 | Polymorphic owner                                     |
| `file_name`    | TEXT                 | Original filename                                     |
| `content_type` | TEXT                 |                                                       |
| `size_bytes`   | BIGINT               |                                                       |
| `storage_key`  | TEXT NOT NULL        | Object storage path `tenants/{tenant_id}/...`         |
| `status`       | TEXT                 | `pending`, `ready`, `deleted`                         |
| `uploaded_by`  | UUID FK → users NULL | Null for public apply uploads                         |
| `created_at`   | TIMESTAMPTZ          |                                                       |
| `deleted_at`   | TIMESTAMPTZ NULL     |                                                       |

**Indexes:** `(tenant_id, owner_type, owner_id)`

### 3.16 `audit_events`

Generic security / admin audit trail.

| Column          | Type        | Notes                                                |
| --------------- | ----------- | ---------------------------------------------------- |
| `id`            | UUID PK     |                                                      |
| `tenant_id`     | UUID NULL   | Null for platform-level                              |
| `actor_user_id` | UUID NULL   |                                                      |
| `action`        | TEXT        | e.g. `user.login`, `job.published`, `offer.accepted` |
| `entity_type`   | TEXT        |                                                      |
| `entity_id`     | UUID        |                                                      |
| `metadata`      | JSONB       | Non-sensitive context                                |
| `ip_address`    | INET        |                                                      |
| `occurred_at`   | TIMESTAMPTZ |                                                      |

---

## 4. Optional / later tables

| Table                     | Purpose                                                 |
| ------------------------- | ------------------------------------------------------- |
| `job_requisitions`        | Split from jobs when formal approval chains exist       |
| `job_members`             | Assign hiring managers / interviewers to jobs           |
| `candidate_tags` + `tags` | Normalized tagging                                      |
| `email_messages`          | Deeper outbound provider sync (beyond `communications`) |
| `api_keys`                | Tenant integrations                                     |
| `subscriptions`           | Billing                                                 |

---

## 5. Referential & tenancy integrity rules

1. `applications.job_id` and `applications.candidate_id` must reference rows with the same `tenant_id` as the application.
2. `applications.tenant_id`, `applications.candidate_id`, and `applications.job_id` are immutable after insert.
3. Child rows (`interviews`, `offers`, `communications`, etc.) inherit and store `tenant_id` for query efficiency and isolation.
4. Public apply must resolve tenant **from the job’s apply token**, never from client-supplied free-form tenant ids alone.
5. Deletes of tenants are operational events (export + purge), not casual cascades in app UI.
6. Prefer restrict/soft-delete on jobs with applications; do not orphan history.

---

## 6. Enumerations (canonical values)

Align with RECRUITMENT_WORKFLOW.md and PRODUCT_REQUIREMENTS.md:

- **Job status:** `draft`, `open`, `on_hold`, `closed`, `filled`
- **Application lifecycle status:** `active`, `hired`, `disqualified`, `withdrawn`, `transferred` (system-level; separate from pipeline stage)
- **Application stages:** `applied`, `cv_screening`, `phone_screening`, `interview`, `reference_check`, `offer`, `pre_hire`, `hired`, `rejected`, `withdrawn`
- **Offer status:** `draft`, `sent`, `accepted`, `declined`, `rescinded`, `expired`
- **Checklist item status:** `pending`, `completed`, `waived`
- **Checklist item type:** `document_upload`, `acknowledgment`, `manual_confirm`
- **Communication type:** `regret_letter`, `offer_letter`, `general`
- **Interview status:** `scheduled`, `completed`, `canceled`, `no_show`
- **Recommendation:** `strong_yes`, `yes`, `neutral`, `no`, `strong_no`
- **Reference outcome:** `positive`, `neutral`, `negative`, `unable_to_reach`
- **Membership roles:** `tenant_owner`, `company_admin`, `recruiter`, `hiring_manager`, `interviewer`, `viewer`

Store as text with check constraints or Postgres enums. Text + check is more migration-friendly early on.

---

## 7. Indexing & performance guidance

| Access pattern         | Supporting index                                            |
| ---------------------- | ----------------------------------------------------------- |
| Board by job           | `(tenant_id, job_id, current_job_stage_id)` on applications |
| Public apply lookup    | unique `jobs.public_apply_token`                            |
| Candidate search       | `(tenant_id, email)`, trigram/`ILIKE` strategy later        |
| Upcoming interviews    | `(tenant_id, scheduled_starts_at)` WHERE status = scheduled |
| Stage history timeline | `(application_id, occurred_at)`                             |
| Regret letter audit    | `(application_id, type)` on communications                  |

Avoid premature micro-indexes; add from measured query plans.

---

## 8. Data retention & privacy

| Data                    | Policy intent                                   |
| ----------------------- | ----------------------------------------------- |
| Stage events            | Retain for audit; purge with tenant offboarding |
| Resumes / pre-hire docs | Delete from storage on candidate purge request  |
| Consent fields          | Retain with application for compliance evidence |
| Auth logs               | Retain limited window (e.g., 90–180 days)       |
| Soft-deleted rows       | Periodically hard-purge per policy              |

Support tenant-level export (JSON/CSV) as a design goal for GDPR readiness.

---

## 9. Migration strategy (when coding begins)

1. Create baseline migration from this model
2. Seed default `pipeline_stages` per new tenant in provisioning transaction
3. Never edit historical stage event rows in place
4. Expand schema via additive migrations; avoid destructive changes without dual-write plans

---

## 10. Example transactions

### 10.1 Public apply

1. Resolve job by `public_apply_token`; verify `status = open` and `apply_enabled`
2. Upsert candidate by `(tenant_id, email)`
3. Insert `applications` (defaults into job Applied entry stage via `is_applied_entry`)
4. Insert `application_stage_events` (`event_type=initial`, snapshots, `actor_user_id` null for public)
5. Store resume `files` row owned by application/candidate

### 10.2 Offer accepted → pre-hire

1. Update offer `status = accepted`, `accepted_at = now()`
2. Transition application `offer` → `pre_hire` + stage event
3. Seed default `application_checklist_items`

### 10.3 Reject + regret letter

1. Transition to `rejected` with `reason_code`
2. Insert `communications` row type `regret_letter`, status `sent` (manual log)

---

## 11. Related documents

- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)
- [RECRUITMENT_WORKFLOW.md](./RECRUITMENT_WORKFLOW.md)
- [USER_ROLES.md](./USER_ROLES.md)
- [SYSTEM_ARCHITECTURE.md](./SYSTEM_ARCHITECTURE.md)
- [PRODUCT_REQUIREMENTS.md](./PRODUCT_REQUIREMENTS.md)
