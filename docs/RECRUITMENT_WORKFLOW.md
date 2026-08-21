# Recruitment Workflow

**Product:** HireFlow  
**Purpose:** Define the canonical hiring pipeline, stage meanings, allowed transitions, and operational rules.  
**Status:** Baseline (source of truth) — aligned with IMPLEMENTATION_PLAN.md (2026-08-04)

This document governs how applications move through HireFlow. UI, API validation, and database constraints must align with these rules.

---

## 1. Core concepts

| Concept                | Definition                                                                               |
| ---------------------- | ---------------------------------------------------------------------------------------- |
| **Job**                | A requisition/opening: starts as a department request (`draft`), then published (`open`) |
| **Candidate**          | A person in the talent pool (identity-level record; **no login account**)                |
| **Application**        | A candidate’s candidacy for a specific job; owns pipeline stage                          |
| **Stage**              | Discrete step in the hiring pipeline for an application                                  |
| **Transition**         | Valid move from one stage to another, with actor + optional note                         |
| **Interview**          | Scheduled evaluation event linked to an application                                      |
| **Offer**              | First-class commercial offer record (not only a stage label)                             |
| **Pre-hire checklist** | Documents and signature acknowledgments required before `hired`                          |
| **Communication**      | Logged outbound message (e.g. regret letter); not a pipeline stage                       |
| **Decision**           | Terminal outcome: hired, rejected, or withdrawn                                          |

**Rule:** Pipeline state lives on the **application**, not the candidate. A candidate may have multiple applications in different stages across jobs.

**Rule:** Candidates never authenticate. They only submit via the public apply page (or are entered manually by the Recruiter).

---

## 2. Business process mapping

|   # | Business step                           | System representation                               |
| --: | --------------------------------------- | --------------------------------------------------- |
|   1 | Department requests a new employee      | Job created in `draft` with requester + HM metadata |
|   2 | HR prepares / updates Job Description   | Job content edited while `draft`                    |
|   3 | HR publishes the Job                    | Job → `open`; public apply link enabled             |
|   4 | Candidates apply                        | Public form → Candidate + Application at `applied`  |
|   5 | CV Filtering                            | Stage `cv_screening`                                |
|   6 | Phone Screening                         | Stage `phone_screening`                             |
|   7 | Schedule interviews with Hiring Manager | Interview records; stage `interview`                |
|   8 | Hiring Manager evaluates                | Interview feedback (entered by Recruiter in MVP)    |
|   9 | Reference Check                         | Stage `reference_check`                             |
|  10 | Prepare Offer Letter                    | Stage `offer` + Offer record                        |
|  11 | Candidate accepts                       | Offer status → `accepted` → move to `pre_hire`      |
|  12 | Collect documents                       | Pre-hire checklist items                            |
|  13 | Sign JD and Offer                       | Checklist acknowledgments (manual confirm in MVP)   |
|  14 | Hired                                   | Stage `hired`; optionally mark Job `filled`         |
|  15 | Regret Letters                          | Reject → log Communication `regret_letter`          |

---

## 3. Default pipeline stages (MVP)

HireFlow ships a default ordered pipeline per tenant:

| Order | Stage key         | Display name    | Type               | Description                                            |
| ----: | ----------------- | --------------- | ------------------ | ------------------------------------------------------ |
|     1 | `applied`         | Applied         | Active             | Application received via public form or manual entry   |
|     2 | `cv_screening`    | CV Screening    | Active             | Recruiter reviews resume against JD                    |
|     3 | `phone_screening` | Phone Screening | Active             | Recruiter phone / initial screen                       |
|     4 | `interview`       | Interview       | Active             | One or more interviews (typically with Hiring Manager) |
|     5 | `reference_check` | Reference Check | Active             | Reference verification in progress                     |
|     6 | `offer`           | Offer           | Active             | Offer prepared / sent / awaiting response              |
|     7 | `pre_hire`        | Pre-Hire        | Active             | Documents collected; JD & offer acknowledgments        |
|     8 | `hired`           | Hired           | Terminal (success) | Employee hire recorded                                 |
|     9 | `rejected`        | Rejected        | Terminal (closed)  | Not moving forward                                     |
|    10 | `withdrawn`       | Withdrawn       | Terminal (closed)  | Candidate withdrew                                     |

### Stage usage notes

- `assessment` (take-home/test) is **not** in the default MVP pipeline; may be added later per tenant.
- Multiple interviews occur while the application remains in `interview` (separate Interview records).
- `offer` requires an Offer record for a complete happy path (see §8).
- `pre_hire` is required after offer acceptance before `hired`.
- Terminal stages end active pipeline work for that application.
- Regret letters are **communications**, not a stage.

---

## 4. Stage lifecycle diagram

```text
                         ┌─────────────┐
                         │   applied   │
                         └──────┬──────┘
                                │
                                ▼
                         ┌──────────────┐
                         │ cv_screening │
                         └──────┬───────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ phone_screening │
                       └────────┬────────┘
                                │
                                ▼
                         ┌─────────────┐
                         │  interview  │  (1..N interview records)
                         └──────┬──────┘
                                │
                                ▼
                      ┌──────────────────┐
                      │ reference_check  │
                      └────────┬─────────┘
                               │
                               ▼
                         ┌─────────────┐
                         │    offer    │  (+ Offer entity)
                         └──────┬──────┘
                                │ accepted
                                ▼
                         ┌─────────────┐
                         │  pre_hire   │  (checklist)
                         └──────┬──────┘
                                │
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                 ▼
         ┌────────┐      ┌──────────┐      ┌───────────┐
         │ hired  │      │ rejected │      │ withdrawn │
         └────────┘      └──────────┘      └───────────┘
```

Terminal stages (`hired`, `rejected`, `withdrawn`) can be reached from any **active** stage when business reality requires it (e.g. reject after CV screening, withdraw during offer).

---

## 5. Transition rules

### 5.1 Forward (happy path)

Allowed forward moves (skipping permitted with a note recommended):

| From              | Allowed next (forward)                                                          |
| ----------------- | ------------------------------------------------------------------------------- |
| `applied`         | `cv_screening`, `phone_screening`, `rejected`, `withdrawn`                      |
| `cv_screening`    | `phone_screening`, `interview`, `rejected`, `withdrawn`                         |
| `phone_screening` | `interview`, `rejected`, `withdrawn`                                            |
| `interview`       | `reference_check`, `offer`, `interview` (re-interview), `rejected`, `withdrawn` |
| `reference_check` | `offer`, `interview`, `rejected`, `withdrawn`                                   |
| `offer`           | `pre_hire`, `rejected`, `withdrawn`, `interview` (rare reopen)                  |
| `pre_hire`        | `hired`, `offer`, `rejected`, `withdrawn`                                       |

**Happy-path expectation:**  
`applied` → `cv_screening` → `phone_screening` → `interview` → `reference_check` → `offer` → `pre_hire` → `hired`

### 5.2 Backward moves

Backward moves are allowed for active stages when correcting mistakes or reopening evaluation:

- Example: `offer` → `interview` if negotiation fails and another loop is needed
- Example: `pre_hire` → `offer` if offer terms change
- Example: `interview` → `phone_screening` if prerequisites were missed

**Requirement:** Every backward move should capture a note (recommended mandatory in UI).

### 5.3 Terminal rules

| Rule                                                      | Detail                                                                                    |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| No further pipeline moves from terminal stages by default | Re-open requires explicit “reopen application” action                                     |
| Reopen                                                    | Moves from terminal → chosen active stage; logged as special transition                   |
| Hire side effect                                          | May set job to `filled` when openings count is met (MVP: recruiter chooses)               |
| Reject / withdraw                                         | Does not auto-close the job                                                               |
| Regret letter                                             | On reject (and optionally when role is filled), Recruiter logs/sends regret communication |

### 5.4 Validation requirements (system)

Every transition must record:

1. `application_id`
2. `from_stage` / `to_stage`
3. `actor_user_id` (Recruiter in MVP; null only for system-generated initial `applied` from public form — then attribute as system/public)
4. `occurred_at`
5. `note` (optional except where mandated)
6. `reason_code` (required when entering `rejected`)

For public apply: initial event may use `actor_user_id = null` with `note` / metadata indicating `submitted_via = public_form`.

---

## 6. Reject reason codes (MVP)

| Code                        | Label                                |
| --------------------------- | ------------------------------------ |
| `skills_mismatch`           | Skills mismatch                      |
| `experience_level`          | Experience level                     |
| `compensation`              | Compensation expectations            |
| `culture_fit`               | Culture / values fit                 |
| `role_filled`               | Role filled by another candidate     |
| `incomplete_process`        | Incomplete process / no-show pattern |
| `references_unsatisfactory` | Unsatisfactory references            |
| `offer_declined`            | Offer declined by candidate          |
| `other`                     | Other (note required)                |

---

## 7. Interview workflow

### 7.1 When interviews happen

- Primary stage: `interview`
- Phone screening is its **own stage** (`phone_screening`), not merely an interview type — though a phone-screen Interview record may still be logged for scheduling.
- Completing an interview does **not** automatically advance the stage

### 7.2 Interview types

| Type key         | Label                    |
| ---------------- | ------------------------ |
| `phone_screen`   | Phone screen             |
| `hiring_manager` | Hiring manager interview |
| `technical`      | Technical interview      |
| `behavioral`     | Behavioral / cultural    |
| `panel`          | Panel interview          |
| `other`          | Other                    |

### 7.3 Interview statuses

`scheduled` → `completed` | `canceled` | `no_show`

### 7.4 Feedback model (MVP)

| Field          | Required | Notes                                                   |
| -------------- | -------- | ------------------------------------------------------- |
| Recommendation | Yes      | `strong_yes`, `yes`, `neutral`, `no`, `strong_no`       |
| Overall notes  | Yes      | Free text                                               |
| Score (1–5)    | No       | Optional numeric                                        |
| On behalf of   | No       | Free text / HM name when Recruiter enters HM evaluation |

**MVP rule:** Hiring Manager has **no login**. Recruiter schedules interviews and enters HM evaluation into feedback (attributed to the Recruiter user, with HM name noted).

**Rule:** At least one completed interview with feedback is recommended before moving to `offer`, but not hard-blocked in MVP (warning in UI is enough).

---

## 8. Offer, pre-hire & hire workflow

### 8.1 Offer entity statuses

| Status      | Meaning                                       |
| ----------- | --------------------------------------------- |
| `draft`     | Letter being prepared                         |
| `sent`      | Extended to candidate                         |
| `accepted`  | Candidate accepted                            |
| `declined`  | Candidate declined                            |
| `rescinded` | Company withdrew offer                        |
| `expired`   | Past expiry without acceptance (optional use) |

### 8.2 Offer stage expectations

While in `offer`, Recruiter should:

1. Create/update an Offer record (`draft` → `sent`)
2. Capture compensation summary, proposed start date, optional expiry
3. On acceptance: set Offer `accepted` and move application to `pre_hire`
4. On decline: typically `rejected` with reason `offer_declined` (or `withdrawn` if candidate-driven framing is preferred)

### 8.3 Pre-hire checklist (MVP defaults)

When entering `pre_hire`, seed checklist items such as:

| Key            | Label                                 | Type                                  |
| -------------- | ------------------------------------- | ------------------------------------- |
| `id_document`  | Identity / right-to-work document     | `document_upload` or `manual_confirm` |
| `signed_offer` | Signed / acknowledged Offer           | `acknowledgment`                      |
| `signed_jd`    | Signed / acknowledged Job Description | `acknowledgment`                      |

MVP does **not** require an e-sign provider. Recruiter uploads files and/or marks items completed manually.

Moving to `hired` should warn (not hard-block in MVP) if required checklist items are still `pending`.

### 8.4 Hired

Transition to `hired` requires:

- Hire date (defaults to today)
- Optional start date
- Confirmation that the application is the selected hire for the job

### 8.5 Job status coupling

| Event                          | Suggested job impact                                                |
| ------------------------------ | ------------------------------------------------------------------- |
| First hire when single opening | Prompt to mark job `filled`                                         |
| Job filled                     | Prompt to reject remaining active applications + log regret letters |
| Multiple openings              | Decrement remaining openings (later); MVP: manual job status        |
| All candidates rejected        | Job remains `open` unless recruiter closes                          |

---

## 9. Regret letters & communications

| Rule                   | Detail                                                                          |
| ---------------------- | ------------------------------------------------------------------------------- |
| Not a stage            | Regret is a **Communication** of type `regret_letter`                           |
| When                   | After `rejected`, and optionally for remaining candidates when role is `filled` |
| MVP delivery           | Recruiter may send externally (email client) and **log as sent** in HireFlow    |
| Required fields on log | `sent_at`, `sent_by`, optional subject/body snapshot                            |
| Later                  | Automated email templates via SMTP/provider                                     |

---

## 10. Job lifecycle (requisition → publish)

| Job status | Meaning                                                            |
| ---------- | ------------------------------------------------------------------ |
| `draft`    | Department request / JD in preparation; **not** publicly applyable |
| `open`     | Published; public apply enabled (if `apply_enabled`)               |
| `on_hold`  | Temporarily paused; apply should be disabled                       |
| `closed`   | No longer hiring; apply disabled                                   |
| `filled`   | Hire(s) completed; apply disabled                                  |

### Publish rules

1. Job must have title + description before publish (enforced in UI; API validation recommended).
2. Publish sets `status = open`, `published_at`, ensures `public_apply_token`, sets `apply_enabled = true`.
3. Public URL uses the apply token (or tenant slug + job slug).

### Requester metadata (MVP fields on Job)

- `requesting_department`
- `requested_by_name`
- `requested_at`
- `hiring_manager_name`
- `hiring_manager_email`

---

## 11. Public apply rules (no candidate account)

1. Unauthenticated POST creates/updates Candidate (dedupe by email within tenant) + Application at `applied`.
2. Resume upload required (PDF/DOC/DOCX).
3. Privacy/GDPR consent checkbox required; store `consent_at` + notice version.
4. Closed / on_hold / filled / `apply_enabled = false` → form unavailable.
5. One active application per candidate+job; re-apply shows a clear message.
6. Candidate receives confirmation only — **no status portal** in MVP.
7. Rate-limit and file size/type limits apply.

---

## 12. Recruiter day-to-day operating loop

1. **Capture request** — create draft job with department + HM contacts
2. **Prepare JD** — edit description until ready
3. **Publish** — open job + share public apply link
4. **Screen** — CV then phone; reject early with reasons
5. **Interview** — schedule HM interviews; capture feedback
6. **References** — complete reference check
7. **Offer → pre-hire → hire** — offer record, checklist, hired
8. **Close the loop** — regret letters for rejected; update job status

SLA guidance (soft, not system-enforced in MVP):

| Stage             | Suggested max dwell |
| ----------------- | ------------------- |
| `applied`         | 2 business days     |
| `cv_screening`    | 3 business days     |
| `phone_screening` | 3 business days     |
| `interview`       | 10 business days    |
| `reference_check` | 5 business days     |
| `offer`           | 5 business days     |
| `pre_hire`        | 5 business days     |

---

## 13. Multi-job & re-application rules

- Same candidate email may have multiple applications across jobs.
- Same candidate should not have two **active** applications for the **same** job.
- Multiple **historical** (non-active) applications for the same candidate + job are allowed; each application row keeps an immutable identity (`tenant_id`, `candidate_id`, `job_id`).
- Lifecycle status (`active` / `hired` / `disqualified` / `withdrawn` / `transferred`) is separate from pipeline stage. Do not treat stage names as lifecycle state.
- New applications enter the job’s designated **Applied entry stage** (`job_stages.is_applied_entry`). Applied and Review are different stages; recruiters move Applied → Review manually.
- Pipeline transitions use `transition_application_stage`. Transitions into hired/closed (lifecycle-terminal) stages are rejected until dedicated lifecycle workflows exist.
- Forward moves that skip intermediate `sort_order` stages require acknowledgement; skipping is allowed after confirm. Backward moves are not treated as skips.
- **Disqualify** is a lifecycle action (category + detailed reason + actor + time), not a pipeline stage. Last `current_job_stage_id` is retained; user-facing outcome is Disqualified.
- **Hired** in Job Workspace is a lifecycle outcome filter (`status = 'hired'`), not a normal Move Stage target.
- Re-application to the same job after a non-active outcome is a **new application row** (future workflow), not rewriting the prior row’s `job_id`.

---

## 14. Customization roadmap

| Capability                                      | Phase    |
| ----------------------------------------------- | -------- |
| Default stages above                            | MVP      |
| Rename stage display labels per tenant          | Post-MVP |
| Add / remove / reorder active stages per tenant | Post-MVP |
| Per-job pipeline templates                      | Later    |
| Required fields / checklists per transition     | Later    |
| Automated emails on transition                  | Post-MVP |
| E-sign provider integration                     | Later    |

Customization must never break historical stage keys already written to the audit log. Prefer stable keys + display labels.

---

## 15. Compliance & fairness notes

- Rejection reasons support consistent reporting and reduce opaque decisions.
- Stage history supports internal audit and candidate data requests.
- Public apply must capture consent for processing.
- Do not encode protected-class attributes as filterable hiring criteria.
- Interview feedback should focus on role-related evidence.

---

## 16. Related documents

- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)
- [PRODUCT_REQUIREMENTS.md](./PRODUCT_REQUIREMENTS.md)
- [USER_ROLES.md](./USER_ROLES.md)
- [DATABASE_DESIGN.md](./DATABASE_DESIGN.md)
- [UI_GUIDELINES.md](./UI_GUIDELINES.md)
