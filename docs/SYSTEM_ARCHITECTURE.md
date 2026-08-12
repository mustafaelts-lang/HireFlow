# System Architecture

**Product:** HireFlow  
**Purpose:** Define technical architecture, multi-tenancy strategy, and system boundaries.  
**Status:** Baseline (source of truth) — aligned with IMPLEMENTATION_PLAN.md (2026-08-04)  
**Constraint:** Documentation only at this stage — no application code yet.

---

## 1. Architectural goals

1. Support a reliable MVP for one recruiter quickly
2. Preserve a clean path to multi-tenant SaaS without data-model rewrites
3. Keep the system operable by a small team (modular monolith preferred initially)
4. Enforce tenant isolation as a hard boundary
5. Prefer boring, proven technology over novelty

---

## 2. High-level architecture

HireFlow will be delivered as a **modular monolith** with a clear split between web client and API, packaged for future extraction of services only if needed.

```text
┌─────────────────────────────────────────────────────────────┐
│                        Clients                              │
│   Recruiter Web App (auth)  │  Public Apply Page (no auth)  │
└─────────────────────────────┬───────────────────────────────┘
                              │ HTTPS / JSON
┌─────────────────────────────▼───────────────────────────────┐
│                     API Application                         │
│  Auth │ Tenancy │ Jobs │ Public Apply │ Candidates │        │
│  Pipeline │ Interviews │ Offers │ Checklist │ Comms │ Files │
└───────┬─────────────────┬───────────────────┬───────────────┘
        │                 │                   │
        ▼                 ▼                   ▼
┌───────────────┐ ┌───────────────┐ ┌─────────────────────────┐
│  PostgreSQL   │ │ Object Storage│ │ Email / async jobs      │
│  (system of   │ │ (resumes,     │ │ (password reset; MVP    │
│   record)     │ │  offer/docs)  │ │  regret = log-only)      │
└───────────────┘ └───────────────┘ └─────────────────────────┘
```

### Repository mapping

| Path                | Responsibility                                         |
| ------------------- | ------------------------------------------------------ |
| `apps/web`          | Recruiter UI + public apply page                       |
| `apps/api`          | HTTP API, domain modules, auth, public apply endpoints |
| `packages/database` | Schema, migrations, persistence helpers                |
| `packages/shared`   | Shared types, constants, validators                    |
| `packages/config`   | Env schema, shared config utilities                    |
| `infrastructure`    | Docker, environment definitions, later IaC             |
| `scripts`           | Dev/ops automation                                     |
| `docs`              | Source of truth                                        |

---

## 3. Multi-tenancy strategy

### 3.1 Chosen approach: shared database, shared schema, row-level tenancy

Every business table includes `tenant_id`.

| Approach                        | Decision                     |
| ------------------------------- | ---------------------------- |
| DB per tenant                   | Rejected for MVP (ops heavy) |
| Schema per tenant               | Rejected for MVP             |
| **Shared schema + `tenant_id`** | **Selected**                 |

### 3.2 Isolation guarantees

- API resolves tenant from the authenticated membership (not from client-supplied free-form ids alone).
- All repositories / queries require tenant scope.
- File object keys: `tenants/{tenant_id}/...`
- Background jobs carry `tenant_id` in payload and re-check on execution.
- Future hardening: PostgreSQL Row Level Security (RLS) as defense in depth.

### 3.3 Tenant provisioning

Creating a tenant creates:

1. `tenants` row
2. Default pipeline stage configuration
3. Owner/recruiter membership
4. Optional seed settings (timezone, reject reasons)

---

## 4. Application style: modular monolith

Domain modules inside the API (logical boundaries):

| Module           | Owns                                                              |
| ---------------- | ----------------------------------------------------------------- |
| `identity`       | Users, credentials, sessions (staff only — no candidate accounts) |
| `tenancy`        | Tenants, memberships, roles                                       |
| `jobs`           | Requisitions/JD, publish, apply tokens                            |
| `public_apply`   | Unauthenticated apply intake scoped by job token                  |
| `candidates`     | Candidates, applications, tags                                    |
| `pipeline`       | Stages, transitions, validation                                   |
| `interviews`     | Interviews, feedback (incl. on-behalf-of HM)                      |
| `references`     | Reference check records                                           |
| `offers`         | Offer records and status changes                                  |
| `checklist`      | Pre-hire checklist items                                          |
| `communications` | Regret letters and outbound message log                           |
| `files`          | Upload metadata, signed URL issuance                              |
| `audit`          | Append-only activity / security events                            |
| `reporting`      | Dashboard aggregates, exports                                     |

Modules communicate in-process via explicit service interfaces. No distributed microservices for MVP.

---

## 5. Suggested technology direction

Final stack selection can be confirmed at implementation kickoff; the architecture assumes:

| Layer            | Recommendation                                        | Rationale                                        |
| ---------------- | ----------------------------------------------------- | ------------------------------------------------ |
| Web              | TypeScript + React (Next.js preferred)                | SSR-friendly public apply + recruiter app        |
| API              | TypeScript (NestJS / Fastify) modular monolith        | One language; clear domain modules               |
| DB               | PostgreSQL                                            | Relational fit for ATS; strong constraints & RLS |
| ORM / SQL        | Prisma, Drizzle, or SQL migrations + query builder    | Migrations mandatory                             |
| Auth             | First-party sessions recommended for MVP              | Simple Recruiter login; no candidate auth        |
| Files            | S3-compatible object storage                          | Resumes, offer PDFs, pre-hire docs               |
| Cache (optional) | Redis                                                 | Sessions / public-apply rate limits later        |
| Email            | Log-only regret in MVP; provider later                | Password reset first; automated notices post-MVP |
| Hosting          | Containerized API + managed Postgres + object storage | Portable and production-like                     |

**Non-requirement:** The documentation does not lock a vendor. Implementation must honor boundaries above.

---

## 6. Request flows (typical)

### 6.1 Authenticated: move application to `interview`

```text
Browser (Recruiter)
  → API auth middleware (validate session/token)
  → tenant context middleware (membership → tenant_id)
  → permission check (pipeline.transition)
  → pipeline service (validate transition rules)
  → persistence transaction:
        update applications.current_job_stage_id
        insert application_stage_events
  → response DTO
```

### 6.2 Unauthenticated: public apply

```text
Browser (Candidate, no account)
  → GET/POST /public/apply/{token}  (no staff session)
  → resolve job by public_apply_token
  → verify job open + apply_enabled
  → rate limit + file validation
  → transaction:
        upsert candidate (tenant_id + email)
        insert application (applied) + consent fields
        insert application_stage_events (actor null / public)
        store resume file metadata
  → confirmation response (no status portal)
```

Failures return typed error codes (validation, forbidden, not found) without leaking cross-tenant existence where avoidable.

---

## 7. File handling architecture

1. Client requests upload intent (`files.write`)
2. API validates type/size and creates `files` metadata row (`pending`)
3. API returns short-lived signed upload URL
4. Client uploads directly to object storage
5. Client confirms upload; API marks file `ready` and links to candidate/application
6. Downloads use signed GET URLs after `files.read` authorization

Never stream arbitrary files through the API long-term unless required for scanning.

---

## 8. Async processing

MVP may run synchronously except:

- Email send (password reset)
- Later: notifications, CSV export generation, virus scan

Use a lightweight job queue when introducing async work (e.g., database-backed queue or Redis queue). Jobs must be tenant-aware and idempotent where possible.

---

## 9. Security architecture

| Control          | Implementation intent                      |
| ---------------- | ------------------------------------------ |
| Transport        | TLS everywhere                             |
| Secrets          | Env / secret manager; never commit         |
| Passwords        | Modern KDF (argon2id / bcrypt)             |
| AuthZ            | Central permission service                 |
| Tenancy          | Mandatory tenant predicate                 |
| Input validation | Schema validation at API boundary          |
| File safety      | Allowlist MIME/extensions; size caps       |
| Rate limiting    | Auth endpoints + public apply first        |
| Audit            | Security + domain events                   |
| Backups          | Automated Postgres backups + restore drill |

---

## 10. Environments

| Environment  | Purpose                               |
| ------------ | ------------------------------------- |
| `local`      | Developer machines via Docker Compose |
| `staging`    | Pre-production verification           |
| `production` | Customer traffic                      |

Configuration via environment variables; no environment-specific secrets in git.

---

## 11. Observability

MVP baseline:

- Structured application logs (JSON) with `request_id`, `tenant_id`, `user_id`
- Error tracking (e.g., Sentry)
- Health endpoints: `/health/live`, `/health/ready`
- Basic metrics: request rate, error rate, latency

Avoid logging PII bodies (resume text, passwords, tokens).

---

## 12. Scalability path

| Stage         | Strategy                                                                    |
| ------------- | --------------------------------------------------------------------------- |
| MVP           | Single API instance + managed Postgres + object storage                     |
| Growth        | Horizontal API replicas behind load balancer; connection pooling            |
| Further       | Read replicas for reporting; extract notification service if needed         |
| Large tenants | Consider RLS + pooling; only then evaluate dedicated DB for enterprise tier |

Do not shard early.

---

## 13. API design principles

- Versioned HTTP JSON API (`/api/v1/...`)
- Resource-oriented endpoints (jobs, candidates, applications, interviews)
- Consistent error shape
- Pagination on list endpoints
- Idempotency keys for critical creates (later)
- OpenAPI spec generated or maintained as contract

---

## 14. Integration architecture (future)

Outbound / inbound integrations plug in behind interfaces:

- Email templates & provider adapter
- Calendar adapter
- Careers page / apply webhook
- HRIS export

Core domain must not depend on a specific vendor SDK at the center of business logic.

---

## 15. Explicit non-architecture (MVP)

- Microservices mesh
- Event-sourcing as primary model (append-only stage events are enough)
- Multi-region active-active
- Client-side-only authorization
- Storing resumes as database BLOBs

---

## 16. Related documents

- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)
- [PRODUCT_REQUIREMENTS.md](./PRODUCT_REQUIREMENTS.md)
- [RECRUITMENT_WORKFLOW.md](./RECRUITMENT_WORKFLOW.md)
- [DATABASE_DESIGN.md](./DATABASE_DESIGN.md)
- [USER_ROLES.md](./USER_ROLES.md)
- [ROADMAP.md](./ROADMAP.md)
- [UI_GUIDELINES.md](./UI_GUIDELINES.md)
