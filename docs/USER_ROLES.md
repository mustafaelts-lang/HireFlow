# User Roles & Access Control

**Product:** HireFlow  
**Purpose:** Define identities, roles, permissions, and tenancy boundaries.  
**Status:** Baseline (source of truth) — aligned with IMPLEMENTATION_PLAN.md (2026-08-04)

HireFlow is multi-tenant. Authorization is always evaluated as:

**authenticated user → tenant membership → role → permission → resource belonging to that tenant**

---

## 1. Identity model

| Entity                   | Description                                                                   |
| ------------------------ | ----------------------------------------------------------------------------- |
| **User**                 | Login identity (email, credentials, profile) — **tenant staff only**          |
| **Tenant**               | Company / organization account                                                |
| **Membership**           | Link between user and tenant with a role                                      |
| **Candidate**            | Data record only — **never a User**; no login                                 |
| **Hiring Manager (MVP)** | Process actor recorded on Job (name/email), not a membership                  |
| **Platform operator**    | HireFlow staff with break-glass / support powers (separate from tenant roles) |

### MVP simplification

- One tenant in active use
- One membership: Recruiter (effectively also acting as Company Admin / Owner)
- Hiring Manager evaluates offline; Recruiter enters feedback on their behalf
- Candidates apply via public form without accounts
- Data model still supports multiple users and roles without redesign

### Future

- A user may belong to multiple tenants (with explicit tenant switcher)
- Hiring Manager and Interviewer become real memberships with job-scoped access
- MVP may constrain to one membership per user to reduce complexity

---

## 2. Role catalog

### 2.1 Tenant roles

| Role key         | Display name   | Purpose                                                         | MVP                                      |
| ---------------- | -------------- | --------------------------------------------------------------- | ---------------------------------------- |
| `tenant_owner`   | Owner          | Billing + full admin + irreversible tenant actions              | Later (map recruiter as owner initially) |
| `company_admin`  | Company Admin  | Manage users, settings, integrations                            | Later                                    |
| `recruiter`      | Recruiter      | Full recruiting operations on jobs & candidates                 | **Yes**                                  |
| `hiring_manager` | Hiring Manager | Review pipeline for owned jobs; feedback; recommend hire        | Phase: multi-user (post-MVP)             |
| `interviewer`    | Interviewer    | View assigned candidates/interviews; submit structured feedback | Post-MVP                                 |
| `viewer`         | Viewer         | Read-only access to permitted jobs                              | Later                                    |

### 2.2 Platform roles (HireFlow operator)

| Role key           | Display name   | Purpose                                              |
| ------------------ | -------------- | ---------------------------------------------------- |
| `platform_admin`   | Platform Admin | Tenant provisioning, support tooling, abuse handling |
| `platform_support` | Support        | Read-only / limited actions for customer support     |

Platform roles never appear in the tenant app UI for customers.

### 2.3 Non-roles (important)

| Actor                | Not a role because                                                                       |
| -------------------- | ---------------------------------------------------------------------------------------- |
| Candidate            | No authentication; public apply only                                                     |
| Hiring Manager (MVP) | Contact metadata on Job + interview feedback “on behalf of”; becomes a role when invited |

---

## 3. Permission model

Permissions are coarse-grained for MVP and can be refined later.

### 3.1 Permission keys

| Permission              | Description                             |
| ----------------------- | --------------------------------------- |
| `tenant.settings.read`  | View company settings                   |
| `tenant.settings.write` | Edit company settings                   |
| `tenant.users.read`     | List members                            |
| `tenant.users.manage`   | Invite, remove, change roles            |
| `jobs.read`             | View jobs                               |
| `jobs.write`            | Create / edit / archive / publish jobs  |
| `candidates.read`       | View candidates & applications          |
| `candidates.write`      | Create / edit candidates & applications |
| `pipeline.transition`   | Move application stages                 |
| `interviews.read`       | View interviews                         |
| `interviews.write`      | Schedule / update interviews            |
| `feedback.write`        | Submit interview feedback               |
| `offers.write`          | Create / update offers                  |
| `checklist.write`       | Complete pre-hire checklist items       |
| `decisions.write`       | Hire / reject / withdraw                |
| `communications.write`  | Log regret letters / outbound messages  |
| `files.read`            | Download resumes / attachments          |
| `files.write`           | Upload attachments                      |
| `reports.read`          | View dashboards / exports               |
| `audit.read`            | View audit / stage history              |

### 3.2 Public apply (unauthenticated)

Public apply is **not** a permission on a membership. It is a separate, tightly scoped unauthenticated API surface:

| Action                                  | Rule                                                                       |
| --------------------------------------- | -------------------------------------------------------------------------- |
| Read job apply form metadata            | Allowed only via valid `public_apply_token` for an open, apply-enabled job |
| Submit application + resume             | Same token scope; creates candidate/application in that tenant only        |
| Read other candidates / stages / offers | **Forbidden**                                                              |

### 3.3 Role → permission matrix

| Permission              | Owner | Admin | Recruiter | Hiring Manager | Interviewer | Viewer |
| ----------------------- | :---: | :---: | :-------: | :------------: | :---------: | :----: |
| `tenant.settings.read`  |   ✓   |   ✓   |     ✓     |       —        |      —      |   —    |
| `tenant.settings.write` |   ✓   |   ✓   |    —*     |       —        |      —      |   —    |
| `tenant.users.read`     |   ✓   |   ✓   |     ✓     |       —        |      —      |   —    |
| `tenant.users.manage`   |   ✓   |   ✓   |     —     |       —        |      —      |   —    |
| `jobs.read`             |   ✓   |   ✓   |     ✓     |       ✓†       |     ✓†      |   ✓†   |
| `jobs.write`            |   ✓   |   ✓   |     ✓     |       —        |      —      |   —    |
| `candidates.read`       |   ✓   |   ✓   |     ✓     |       ✓†       |     ✓†      |   ✓†   |
| `candidates.write`      |   ✓   |   ✓   |     ✓     |    limited‡    |      —      |   —    |
| `pipeline.transition`   |   ✓   |   ✓   |     ✓     |    limited‡    |      —      |   —    |
| `interviews.read`       |   ✓   |   ✓   |     ✓     |       ✓†       |     ✓†      |   —    |
| `interviews.write`      |   ✓   |   ✓   |     ✓     |    limited‡    |      —      |   —    |
| `feedback.write`        |   ✓   |   ✓   |     ✓     |       ✓        |      ✓      |   —    |
| `offers.write`          |   ✓   |   ✓   |     ✓     |       —        |      —      |   —    |
| `checklist.write`       |   ✓   |   ✓   |     ✓     |       —        |      —      |   —    |
| `decisions.write`       |   ✓   |   ✓   |     ✓     | recommend only |      —      |   —    |
| `communications.write`  |   ✓   |   ✓   |     ✓     |       —        |      —      |   —    |
| `files.read`            |   ✓   |   ✓   |     ✓     |       ✓†       |     ✓†      |   —    |
| `files.write`           |   ✓   |   ✓   |     ✓     |       —        |      —      |   —    |
| `reports.read`          |   ✓   |   ✓   |     ✓     |       ✓†       |      —      |   ✓†   |
| `audit.read`            |   ✓   |   ✓   |     ✓     |       —        |      —      |   —    |

\* MVP: sole recruiter may also hold Owner/Admin capabilities until multi-user admin ships.  
† Scoped to assigned / owned jobs when scoping is introduced.  
‡ Hiring managers may add notes / request stage changes; hard transitions remain recruiter-owned unless configured otherwise.

---

## 4. Resource scoping rules

### 4.1 Tenant isolation (hard rule)

- Every query for jobs, candidates, applications, interviews, offers, files, and audit events **must** filter by `tenant_id`.
- Cross-tenant access is forbidden except via platform operator tools with explicit audit.
- Object storage keys must be prefixed by tenant id.
- Public apply resolves tenant from the **job token**, then writes only within that tenant.

### 4.2 Job scoping (post-MVP)

When Hiring Managers / Interviewers are introduced:

| Role                      | Default visibility                            |
| ------------------------- | --------------------------------------------- |
| Recruiter / Admin / Owner | All jobs in tenant                            |
| Hiring Manager            | Jobs where user is listed as hiring manager   |
| Interviewer               | Applications / interviews explicitly assigned |
| Viewer                    | Jobs explicitly shared                        |

MVP: Recruiter sees all tenant data. Job stores `hiring_manager_name` / `hiring_manager_email` for process context only.

---

## 5. Authentication requirements

| Topic           | MVP decision                                             |
| --------------- | -------------------------------------------------------- |
| Staff method    | Email + password                                         |
| Candidate auth  | None                                                     |
| Session         | HTTP-only secure cookie or bearer access token + refresh |
| Password policy | Minimum length 10; breached-password check recommended   |
| MFA             | Later (Should for Owner/Admin)                           |
| Invite flow     | Magic invite link sets password (post-MVP)               |
| Deactivation    | Soft-disable membership; revoke sessions                 |

---

## 6. Authorization enforcement layers

1. **API gateway / middleware** — authenticate identity (skip only for public apply routes)
2. **Tenant context resolver** — from membership **or** from job apply token on public routes
3. **Permission check** — role allows action (authenticated routes)
4. **Resource ownership check** — target row’s `tenant_id` matches context
5. **Optional job assignment check** — for restricted roles (later)

UI may hide actions, but **server-side enforcement is mandatory**.

---

## 7. Audit expectations by role

Always audited:

- Login success/failure (security log)
- Job publish / apply-link enable
- Stage transitions
- Offer status changes
- Hire / reject / withdraw decisions
- Regret letter communications logged
- Role changes and user invites
- Resume downloads (recommended; MVP optional)

Actors must be attributable to a user id (or `null` + metadata for public apply intake).

---

## 8. MVP role plan

For the first production slice:

1. Provision one tenant (company).
2. Provision one user with role `recruiter`.
3. Treat that user as de facto Owner for settings until Admin UI exists.
4. Do not build multi-role UI yet; keep permission checks centralized so roles can be enabled without schema rewrite.
5. Represent Hiring Manager as job fields + feedback `on_behalf_of_name`, not as a membership.

### Seed policy

```text
tenant: Acme Corp (example)
user: recruiter@acme.example
role: recruiter (+ owner capabilities temporarily)
```

---

## 9. Future: least privilege defaults

When inviting users:

| Invite as      | Default                         |
| -------------- | ------------------------------- |
| Recruiter      | Full recruiting permissions     |
| Hiring Manager | Job-scoped read + feedback      |
| Interviewer    | Assignment-scoped feedback only |

Owners should prefer Interviewer over Recruiter for occasional panelists.

---

## 10. Related documents

- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)
- [PRODUCT_REQUIREMENTS.md](./PRODUCT_REQUIREMENTS.md)
- [RECRUITMENT_WORKFLOW.md](./RECRUITMENT_WORKFLOW.md)
- [SYSTEM_ARCHITECTURE.md](./SYSTEM_ARCHITECTURE.md)
- [DATABASE_DESIGN.md](./DATABASE_DESIGN.md)
