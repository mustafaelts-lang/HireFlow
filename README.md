# HireFlow

HireFlow is a production-ready, multi-tenant SaaS Applicant Tracking System (ATS) designed to help recruiting teams manage job openings, candidates, interviews, and hiring decisions in one place.

It follows a **real HR recruitment process**: department request → job description → publish → public apply → CV/phone screening → interviews → references → offer → pre-hire documents/signatures → hired, plus regret letters for rejected candidates.

## Current phase

**Phase 0 complete** — documentation aligned to the real business workflow. No application code has been written yet.

The MVP will initially serve a **single HR Recruiter**. Candidates have **no accounts** and apply only through a **public application page**. The architecture and data model are designed from day one for multi-company (multi-tenant) scale.

## Repository layout

```
HireFlow/
├── docs/                    # Product & engineering source of truth
├── apps/
│   ├── web/                 # Recruiter web app + public apply page (future)
│   └── api/                 # Backend API / services (future)
├── packages/
│   ├── shared/              # Shared types, utilities, constants (future)
│   ├── database/            # Schema, migrations, data access (future)
│   └── config/              # Shared configuration (future)
├── infrastructure/
│   ├── docker/              # Local & deploy container definitions (future)
│   └── environments/        # Environment-specific config (future)
├── scripts/                 # Operational & developer scripts (future)
└── .github/workflows/       # CI/CD pipelines (future)
```

## Documentation (source of truth)

| Document                                                | Purpose                                           |
| ------------------------------------------------------- | ------------------------------------------------- |
| [IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md)   | Workflow analysis, entities, phased build plan    |
| [PRODUCT_REQUIREMENTS.md](docs/PRODUCT_REQUIREMENTS.md) | Product vision, MVP scope, and requirements       |
| [RECRUITMENT_WORKFLOW.md](docs/RECRUITMENT_WORKFLOW.md) | End-to-end hiring pipeline and stage rules        |
| [USER_ROLES.md](docs/USER_ROLES.md)                     | Roles, permissions, and access model              |
| [SYSTEM_ARCHITECTURE.md](docs/SYSTEM_ARCHITECTURE.md)   | Technical architecture and multi-tenancy approach |
| [DATABASE_DESIGN.md](docs/DATABASE_DESIGN.md)           | Logical data model and entity relationships       |
| [UI_GUIDELINES.md](docs/UI_GUIDELINES.md)               | UX principles and interface standards             |
| [ROADMAP.md](docs/ROADMAP.md)                           | Phased delivery from MVP to full SaaS             |

## Guiding principles

1. **Docs first** — product and architecture decisions live in `/docs` before implementation.
2. **Real HR workflow** — stages and entities mirror how recruiting actually operates.
3. **Multi-tenant ready** — tenant isolation is a first-class concern even while MVP serves one company.
4. **One Recruiter MVP** — Hiring Manager is an offline process actor until multi-user ships.
5. **No candidate accounts** — public apply in; recruiter-owned status.
6. **Ship the smallest useful product** — one recruiter can run a full hire loop before expanding roles and integrations.

## Default MVP pipeline

`applied` → `cv_screening` → `phone_screening` → `interview` → `reference_check` → `offer` → `pre_hire` → `hired`  
(+ `rejected` / `withdrawn`)

## Next steps

1. Confirm stack decisions (see IMPLEMENTATION_PLAN.md §8 and open questions in the PRD).
2. Begin **Phase 1** scaffolding (`apps/*`, `packages/database`) per [docs/ROADMAP.md](docs/ROADMAP.md).
3. Keep `/docs` updated when decisions change; docs remain the contract.
