# Product Requirements Document (PRD)

**Product:** HireFlow  
**Type:** Multi-tenant SaaS Applicant Tracking System (ATS)  
**Document status:** Baseline (source of truth) — aligned with IMPLEMENTATION_PLAN.md (2026-08-04)  
**Primary MVP user:** Single HR recruiter  
**Long-term model:** Multiple companies (tenants), multiple users per tenant

---

## 1. Vision

HireFlow helps recruiting teams move candidates from application to hire with clarity, speed, and accountability. It replaces scattered spreadsheets, inboxes, and ad-hoc chat with a structured pipeline that is easy for one recruiter to run today and ready for multi-company scale tomorrow.

**Product promise:** Every open role has a clear pipeline. Every candidate has a clear status. Every decision is traceable.

---

## 2. Problem statement

Growing teams lose hiring signal in:

- Unstructured email threads and CV folders
- Spreadsheets that cannot enforce stage rules or ownership
- Interview feedback that never reaches a decision
- Missing pre-hire document / signature tracking before “hired”
- Inconsistent regret letters after rejection
- Tools that are either too heavy (enterprise ATS) or too shallow (forms + sheets)

HireFlow targets the gap: a focused ATS that mirrors a real HR recruitment process, operationally complete for a recruiter MVP, architected as multi-tenant SaaS from the start.

---

## 3. Goals and non-goals

### 3.1 Goals (MVP)

| ID  | Goal                                                                     | Success signal                                                 |
| --- | ------------------------------------------------------------------------ | -------------------------------------------------------------- |
| G1  | A recruiter can capture a department headcount request and publish a job | Draft → open job with public apply link                        |
| G2  | Candidates can apply without an account                                  | Public apply creates candidate + application + resume          |
| G3  | A recruiter can run the real selection pipeline                          | CV → phone → interview → references → offer → pre-hire → hired |
| G4  | A recruiter can schedule interviews and capture HM evaluation            | Interview + feedback records exist                             |
| G5  | A recruiter can manage offer acceptance and pre-hire docs                | Offer statuses + checklist completion                          |
| G6  | A recruiter can reject with reason and log regret letters                | Terminal reject + communication log                            |
| G7  | Foundation supports future multi-tenancy                                 | `tenant_id` everywhere; isolation tested                       |

### 3.2 Non-goals (MVP)

- Candidate self-service accounts / status portal
- Branded multi-job public careers site (single-job apply page is in scope)
- Hiring Manager or Interviewer logins
- Deep HRIS / payroll integrations
- AI resume scoring as a core dependency
- Full offer-letter generation / e-sign provider (upload + manual acknowledgment is enough)
- Automated SMTP email delivery (manual “log as sent” is enough)
- Mobile-native apps
- Billing / marketplace portals

---

## 4. Target users

| Persona                   | MVP                                | Later                | Primary jobs-to-be-done                             |
| ------------------------- | ---------------------------------- | -------------------- | --------------------------------------------------- |
| **HR Recruiter**          | Yes                                | Yes                  | Run the full pipeline end-to-end                    |
| Hiring Manager            | Offline actor only                 | Yes (login)          | Evaluate candidates; later submit feedback directly |
| Interviewer               | No                                 | Yes                  | View assigned interviews; submit feedback           |
| Company Admin             | Implicit (recruiter)               | Yes                  | Manage users, settings, integrations                |
| Platform Admin (HireFlow) | Internal                           | Yes                  | Operate tenants, billing, support                   |
| Candidate                 | **No account** — public apply only | Optional status page | Submit application + resume                         |

MVP assumption: one authenticated recruiter user operating inside one tenant (company). Hiring Manager name/email is stored on the job; Recruiter enters HM feedback on their behalf.

---

## 5. Product principles

1. **Pipeline clarity over feature density** — stage state must always be obvious.
2. **Auditability** — who moved what, when, and why.
3. **Tenant-safe by design** — no cross-company data leakage, even with one tenant in MVP.
4. **Real HR process fidelity** — stages match how recruiting actually works.
5. **Minimal friction** — publish job → receive apply → move stage in as few steps as possible.
6. **Progressive complexity** — HM portals, automation, and integrations unlock after the core loop works.

---

## 6. Functional requirements

### 6.1 Authentication & tenancy

| ID    | Requirement                                     | Priority |
| ----- | ----------------------------------------------- | -------- |
| FR-A1 | Users authenticate with email + password (MVP)  | Must     |
| FR-A2 | Every user belongs to exactly one tenant in MVP | Must     |
| FR-A3 | All business data is scoped by `tenant_id`      | Must     |
| FR-A4 | Session / token invalidation on logout          | Must     |
| FR-A5 | Password reset via email                        | Should   |
| FR-A6 | SSO / SAML                                      | Later    |
| FR-A7 | Candidates do not authenticate                  | Must     |

### 6.2 Jobs (requisitions)

| ID    | Requirement                                                                                | Priority |
| ----- | ------------------------------------------------------------------------------------------ | -------- |
| FR-J1 | Create / edit / archive job openings                                                       | Must     |
| FR-J2 | Job fields: title, department, location, employment type, description, status              | Must     |
| FR-J3 | Job statuses: `draft`, `open`, `on_hold`, `closed`, `filled`                               | Must     |
| FR-J4 | Capture request metadata: requesting department, requested by, requested at, HM name/email | Must     |
| FR-J5 | Publish action enables public apply token/link                                             | Must     |
| FR-J6 | Soft-delete or archive; retain historical candidates                                       | Must     |
| FR-J7 | Duplicate job as template                                                                  | Should   |
| FR-J8 | Headcount / openings count                                                                 | Should   |

### 6.3 Public apply & candidates

| ID     | Requirement                                                  | Priority |
| ------ | ------------------------------------------------------------ | -------- |
| FR-C1  | Public apply page per open job (no candidate account)        | Must     |
| FR-C2  | Apply captures name, email, phone, resume, privacy consent   | Must     |
| FR-C3  | Create/update candidate + application at `applied`           | Must     |
| FR-C4  | Manual candidate entry still supported (referrals/agencies)  | Must     |
| FR-C5  | Candidate can apply to multiple jobs (separate applications) | Must     |
| FR-C6  | Duplicate detection by email within tenant                   | Must     |
| FR-C7  | One active application per candidate+job                     | Must     |
| FR-C8  | Tags / skills free-text or simple tags                       | Should   |
| FR-C9  | Parse resume into structured fields                          | Later    |
| FR-C10 | Candidate status self-service portal                         | Later    |

### 6.4 Pipeline & stages

| ID    | Requirement                                                                                                                     | Priority             |
| ----- | ------------------------------------------------------------------------------------------------------------------------------- | -------------------- |
| FR-P1 | Default stages: applied, cv_screening, phone_screening, interview, reference_check, offer, pre_hire, hired, rejected, withdrawn | Must                 |
| FR-P2 | Move application between stages with validation                                                                                 | Must                 |
| FR-P3 | Record stage change history (actor, timestamp, note, reason)                                                                    | Must                 |
| FR-P4 | Kanban / board view by stage for a job                                                                                          | Must                 |
| FR-P5 | List / table view with filters                                                                                                  | Must                 |
| FR-P6 | Custom stages per tenant                                                                                                        | Should (post-MVP UI) |
| FR-P7 | Custom stages per job                                                                                                           | Later                |

### 6.5 Interviews & feedback

| ID    | Requirement                                                                        | Priority |
| ----- | ---------------------------------------------------------------------------------- | -------- |
| FR-I1 | Schedule interview: type, datetime, interviewer name/email                         | Must     |
| FR-I2 | Interview statuses: `scheduled`, `completed`, `canceled`, `no_show`                | Must     |
| FR-I3 | Capture structured feedback: recommendation + notes; optional on-behalf-of HM name | Must     |
| FR-I4 | Link interview to application                                                      | Must     |
| FR-I5 | Calendar integrations (Google / Outlook)                                           | Later    |
| FR-I6 | Hiring Manager login to submit feedback                                            | Later    |

### 6.6 References, offers, pre-hire, decisions

| ID     | Requirement                                                             | Priority |
| ------ | ----------------------------------------------------------------------- | -------- |
| FR-D1  | Reference check stage; log reference contacts/outcomes                  | Must     |
| FR-D2  | Offer record with statuses draft/sent/accepted/declined/rescinded       | Must     |
| FR-D3  | On offer accept, move to pre_hire and seed checklist                    | Must     |
| FR-D4  | Pre-hire checklist: docs + signed JD + signed offer (manual confirm OK) | Must     |
| FR-D5  | Mark as hired; set hire date / start date; optionally fill job          | Must     |
| FR-D6  | Reject application with reason code                                     | Must     |
| FR-D7  | Log regret letter sent (manual channel OK)                              | Must     |
| FR-D8  | When job filled, helper to reject remaining + log regrets               | Should   |
| FR-D9  | Automated candidate emails                                              | Later    |
| FR-D10 | E-sign provider integration                                             | Later    |

### 6.7 Search, reporting, activity

| ID    | Requirement                                                         | Priority |
| ----- | ------------------------------------------------------------------- | -------- |
| FR-R1 | Search candidates by name / email                                   | Must     |
| FR-R2 | Filter applications by stage, job, source                           | Must     |
| FR-R3 | Basic dashboard: open jobs, active candidates, interviews this week | Should   |
| FR-R4 | Export CSV of applications for a job                                | Should   |
| FR-R5 | Full analytics suite                                                | Later    |

### 6.8 Administration

| ID    | Requirement                                          | Priority |
| ----- | ---------------------------------------------------- | -------- |
| FR-S1 | Tenant profile: company name, timezone, locale       | Must     |
| FR-S2 | Manage users & roles (MVP: single recruiter is fine) | Should   |
| FR-S3 | Audit log of critical actions                        | Should   |
| FR-S4 | Billing / subscription management                    | Later    |

---

## 7. Non-functional requirements

| ID     | Category           | Requirement                                                              |
| ------ | ------------------ | ------------------------------------------------------------------------ |
| NFR-1  | Security           | Encrypt data in transit (TLS); hash passwords; secrets never in source   |
| NFR-2  | Isolation          | Strict tenant scoping on every query and file access path                |
| NFR-3  | Reliability        | Target 99.5%+ availability for MVP hosted environment                    |
| NFR-4  | Performance        | Common list/board views respond within 2s under MVP load                 |
| NFR-5  | Auditability       | Stage transitions and decisions are immutable events                     |
| NFR-6  | Privacy            | Consent on apply; support export / deletion requests (GDPR-ready design) |
| NFR-7  | Observability      | Structured logs, error tracking, basic health checks                     |
| NFR-8  | Maintainability    | Clear module boundaries; migrations for all schema changes               |
| NFR-9  | Scalability        | Architecture allows horizontal API scaling; DB as system of record       |
| NFR-10 | Public apply abuse | Rate limits, file type/size limits; CAPTCHA later if needed              |

---

## 8. MVP scope definition

### In scope

- Single-tenant usage with multi-tenant data model
- Recruiter authentication (no candidate accounts)
- Jobs from department request → draft JD → publish
- Public apply page + resume upload + consent
- Manual candidate entry
- Full selection pipeline (CV, phone, interview, references)
- Interviews + HM feedback entered by Recruiter
- Offers + pre-hire checklist + hire
- Reject + regret letter logging
- File storage for resumes and pre-hire docs
- Basic search, filters, stage history

### Out of scope (MVP)

- Multi-user collaboration (HM/Interviewer logins)
- Branded careers portal
- Automated email / calendar sync
- E-sign vendors
- Billing
- Mobile apps
- AI ranking

### MVP acceptance criteria

A recruiter can, without leaving HireFlow (except sending email externally if needed):

1. Create a draft job from a department request (with HM contact)
2. Publish the job and open a public apply link
3. Receive an application from the public form (candidate has no account)
4. Move a candidate: CV → Phone → Interview (with feedback) → References → Offer
5. Mark offer accepted; complete pre-hire checklist; mark Hired
6. Reject another candidate; log that a regret letter was sent
7. See full stage history for both applications

---

## 9. Constraints and assumptions

- Initial deployment may be single-region.
- English-first UI for MVP.
- File storage via object storage (S3-compatible), not database BLOBs.
- One primary database; no microservices required for MVP.
- Legal / compliance posture: design for GDPR; formal certifications later.
- Hiring Manager participates offline in MVP.

---

## 10. Risks and mitigations

| Risk                                                 | Impact              | Mitigation                                      |
| ---------------------------------------------------- | ------------------- | ----------------------------------------------- |
| Overbuilding multi-tenancy before product-market fit | Delay               | Ship single-user UX; keep tenant_id everywhere  |
| Unclear stage model                                  | Recruiter confusion | Fix default workflow in RECRUITMENT_WORKFLOW.md |
| Public apply spam                                    | Noise / cost        | Tokenized URLs, rate limits, file constraints   |
| Pre-hire scope creep into HRIS                       | Lost focus          | Checklist + files only                          |
| Resume file handling complexity                      | Bugs / security     | Signed URLs; type/size limits; virus-scan later |
| Building HM portals too early                        | Delay               | Recruiter-entered feedback + HM fields on job   |

---

## 11. Open questions

| #   | Question                                                            | Status                                                    |
| --- | ------------------------------------------------------------------- | --------------------------------------------------------- |
| 1   | Will MVP include a public apply form?                               | **Resolved:** Yes — Must                                  |
| 2   | Which auth provider (first-party vs Auth0/Clerk/etc.)?              | Open — recommend first-party sessions                     |
| 3   | Preferred cloud (AWS / Azure / GCP) for first production deploy?    | Open                                                      |
| 4   | Is offer letter generation / e-sign required before first customer? | **Resolved for MVP:** No — upload + manual acknowledgment |
| 5   | Web/API/ORM stack confirmation                                      | Open — see IMPLEMENTATION_PLAN.md §8                      |

Decisions should be recorded in ROADMAP.md decision log when resolved.

---

## 12. Related documents

- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)
- [RECRUITMENT_WORKFLOW.md](./RECRUITMENT_WORKFLOW.md)
- [USER_ROLES.md](./USER_ROLES.md)
- [SYSTEM_ARCHITECTURE.md](./SYSTEM_ARCHITECTURE.md)
- [DATABASE_DESIGN.md](./DATABASE_DESIGN.md)
- [UI_GUIDELINES.md](./UI_GUIDELINES.md)
- [ROADMAP.md](./ROADMAP.md)
