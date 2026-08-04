# UI Guidelines

**Product:** HireFlow  
**Purpose:** UX principles, information architecture, and visual standards for the recruiter product and public apply page.  
**Status:** Baseline (source of truth) — aligned with IMPLEMENTATION_PLAN.md (2026-08-04)  
**Primary surface:** Web application for recruiters (desktop-first, mobile-usable)  
**Secondary surface:** Unauthenticated public apply page (per job)

---

## 1. Product UX mission

HireFlow’s interface should make **pipeline state obvious** and **next actions fast**. A recruiter should always know:

1. Which jobs are open
2. Where each candidate stands in the real HR process
3. What needs attention this week (screens, interviews, offers, pre-hire docs, regret letters)

Clarity beats decoration. Speed beats ceremony.

---

## 2. Design principles

| Principle                      | Meaning in HireFlow                                                                        |
| ------------------------------ | ------------------------------------------------------------------------------------------ |
| **Pipeline first**             | The job board / stage view is the hero workflow, not a buried report                       |
| **Real-process labels**        | Stage names match HR language (CV Screening, Phone Screening, Pre-Hire)                    |
| **One primary action**         | Each screen has a clear main CTA (Publish job, Move stage, Schedule interview, Log regret) |
| **Progressive disclosure**     | Advanced fields (comp details, tags) stay secondary                                        |
| **Trust through history**      | Stage changes, offers, and communications are visible on the application                   |
| **Calm density**               | Tables and boards may be information-rich; avoid noisy widgets and badge spam              |
| **Tenant-safe UX**             | Never show cross-tenant concepts; company context is ambient                               |
| **No candidate portal chrome** | Public apply is a focused form — not a logged-in product shell                             |

---

## 3. Visual direction

HireFlow is an **operations product**, not a marketing site. Apply the following when building UI:

### 3.1 Brand & atmosphere

- Product name **HireFlow** should be clear in the app chrome (sidebar/header), but workspaces are task-led after login.
- Prefer a crisp, professional recruiting-ops look: strong typography hierarchy, generous but disciplined spacing, subtle surface differentiation.
- Avoid generic “AI SaaS” clichés as the default identity: purple-on-white gradients, glow stacks, and ornamental glassmorphism.
- Backgrounds may use subtle gradients or soft structural patterns for depth; keep contrast WCAG-compliant for text and controls.

### 3.2 Typography

- Use purposeful font pairing (e.g., a distinctive sans for UI + a clear monospace only for IDs if needed).
- Do **not** default to Inter / Roboto / Arial / system-only stacks as the brand voice once marketing/app shells are styled.
- Establish type scale tokens: `display`, `title`, `body`, `label`, `caption`.

### 3.3 Color tokens (define in implementation)

Define semantic CSS variables early:

| Token                                 | Role                                |
| ------------------------------------- | ----------------------------------- |
| `--color-bg`                          | App background                      |
| `--color-surface`                     | Panels / sheets                     |
| `--color-border`                      | Dividers                            |
| `--color-text` / `--color-text-muted` | Primary / secondary text            |
| `--color-accent`                      | Primary actions                     |
| `--color-success`                     | Hired / positive                    |
| `--color-warning`                     | On hold / aging / pre-hire pending  |
| `--color-danger`                      | Reject / destructive                |
| `--color-stage-*`                     | Optional stage accents (restrained) |

Stage colors must aid scanning, not become a rainbow. Terminal stages (`hired`, `rejected`, `withdrawn`) need distinct but accessible treatments.

### 3.4 Components philosophy

- **Cards only when they aid interaction** (e.g., interview feedback form, offer editor, checklist). Prefer lists, boards, and plain sections over card grids for browsing.
- Avoid pill overload, stat-strip dashboards on every page, and floating decorative badges.
- Prefer solid, readable buttons with clear hierarchy: primary / secondary / tertiary / destructive.
- Border radius: consistent and moderate — not “fully rounded pill” everything.

### 3.5 Motion

Ship a few intentional motions:

1. Board card stage move (short, physical)
2. Panel / drawer enter for candidate detail
3. Subtle toast for saved transitions

No continuous ambient animation in the ops UI.

---

## 4. Information architecture

### 4.1 Primary navigation (MVP — authenticated Recruiter)

| Nav item       | Purpose                                                                             |
| -------------- | ----------------------------------------------------------------------------------- |
| **Dashboard**  | Today’s focus: open jobs, interviews upcoming, stalled candidates, pending pre-hire |
| **Jobs**       | List + create/edit/publish jobs; copy apply link                                    |
| **Candidates** | Talent pool search across jobs                                                      |
| **Schedule**   | Interview calendar/list (can be combined into Dashboard early)                      |
| **Settings**   | Company profile, account                                                            |

### 4.2 Key screens (Recruiter)

1. **Jobs list** — status, department, HM, candidate counts, apply-link affordance
2. **Job create / edit** — request metadata + JD; primary CTA shifts from Save draft → Publish
3. **Job detail / pipeline board** — columns by active stage; primary working screen
4. **Application detail** — profile, resume, timeline, interviews, references, offer, checklist, communications
5. **Interview schedule + feedback** — recommendation required; optional “on behalf of” HM name
6. **Offer editor** — status, compensation summary, dates, letter file
7. **Pre-hire checklist** — complete / waive items; upload docs

### 4.3 Public apply (unauthenticated)

Single-purpose page — **not** inside the Recruiter app shell:

| Element                  | Guidance                                        |
| ------------------------ | ----------------------------------------------- |
| Job title + company name | Clear, dominant                                 |
| Short role summary       | Optional excerpt from JD                        |
| Form fields              | Name, email, phone, resume, consent             |
| Primary CTA              | “Submit application”                            |
| Success state            | Confirmation only — no status tracking          |
| Closed state             | “This role is no longer accepting applications” |

**Hero budget:** brand/company + job title + one short line + form. No marketing stat strips, no fake “portal” navigation.

### 4.4 Hierarchy rule

**Job → Application (stage) → Events / Interviews / Offer / Checklist / Communications** is the mental model. UI copy and breadcrumbs should reinforce it.

---

## 5. Pipeline board UX

### Active columns (MVP default)

`Applied` · `CV Screening` · `Phone Screening` · `Interview` · `Reference Check` · `Offer` · `Pre-Hire`

Terminal stages (`Hired`, `Rejected`, `Withdrawn`) via filter or “Closed” section.

### Must

- Columns map to active stages from RECRUITMENT_WORKFLOW.md
- Drag-and-drop **or** explicit “Move to…” control (MVP may start with explicit move)
- Candidate card shows: name, source, days in stage, next interview marker
- Empty column states with one action (“Add candidate” / “Share apply link”)

### Must not

- Hide reject/withdraw so deeply that recruiters avoid recording outcomes
- Allow silent stage changes without confirmation when moving to terminal stages
- Overwhelm cards with more than ~4 metadata fields
- Invent a board column for regret letters (use action on reject instead)

### Move-to-terminal pattern

Moving to `rejected` / `withdrawn` / `hired` opens confirmation with required fields (reason code, hire date, etc.).  
On `rejected`, offer secondary action: **Log regret letter**.

### Offer → Pre-Hire pattern

When marking offer `accepted`, confirm and move to `pre_hire` with checklist seeded — surface checklist progress on the card or detail header.

---

## 6. Forms & validation

- Inline validation after submit attempt; preserve user input
- Required fields marked clearly; do not mark every field optional with noise
- Long descriptions: resizable textarea / markdown later
- File upload: show filename, size, replace action; accept PDF/DOC/DOCX for MVP
- Public apply consent: explicit checkbox; do not pre-check

---

## 7. Feedback, empty states, errors

| State           | Guidance                                                           |
| --------------- | ------------------------------------------------------------------ |
| Empty job list  | Explain value + CTA “Create job”                                   |
| Draft job ready | CTA “Publish & get apply link”                                     |
| Empty board     | “Share apply link” + “Add candidate manually”                      |
| Success         | Toast: “Moved to Phone Screening” / “Regret letter logged”         |
| Failure         | Specific: “Could not publish — description required”               |
| Loading         | Skeleton for boards/tables; avoid full-page spinners when possible |

Copy voice: professional, direct, human. No slang, no emoji-dependent UI.

---

## 8. Accessibility

- Keyboard operable board actions and forms
- Visible focus states
- Color is not the only stage signal (label text always present)
- Minimum contrast AA for text
- Meaningful `label` elements; do not rely on placeholder-only forms
- Respect `prefers-reduced-motion`
- Public apply must be fully keyboard usable and screen-reader labeled

---

## 9. Responsive behavior

| Breakpoint   | Behavior                                            |
| ------------ | --------------------------------------------------- |
| Desktop      | Full board + side detail drawer                     |
| Tablet       | Board with horizontal scroll; detail as full page   |
| Mobile       | List-first per stage; move actions via bottom sheet |
| Public apply | Mobile-first form; large tap targets                |

MVP optimization target: desktop recruiter workflow. Mobile must remain usable for status checks and feedback entry. Public apply must work well on mobile.

---

## 10. Content & microcopy standards

- Use **stage names** consistently with RECRUITMENT_WORKFLOW.md
- Prefer verbs: “Move to Offer”, “Schedule interview”, “Mark hired”, “Log regret letter”, “Publish job”
- Avoid internal jargon in UI (`tenant_id`, enum keys)
- Dates: localized; always show timezone for interviews
- Names: show full name; email secondary
- HM offline: copy like “Record hiring manager feedback” rather than “Request HM login”

---

## 11. Permission-aware UI

- Hide actions the user cannot perform
- If an action is visible but blocked, explain why
- MVP single-recruiter: still structure components to accept permission flags later
- Public apply routes never expose Recruiter navigation or other applicants

---

## 12. Out of scope for MVP UI

- Public marketing website design system (can share tokens later)
- Candidate-facing status portal theming
- Heavy customization / white-label per tenant
- Dark mode as a requirement (optional later; do not bias the first design to dark-only)
- Hiring Manager workspace

---

## 13. Implementation checklist (when UI work starts)

- [ ] Tokenized colors, spacing, typography
- [ ] Shared authenticated app shell (nav + content)
- [ ] Jobs list + create/edit + publish + apply link
- [ ] Public apply page (standalone layout)
- [ ] Pipeline board with new stage columns
- [ ] Application detail: timeline, interviews, references, offer, checklist, communications
- [ ] Interview + feedback forms (on-behalf-of HM)
- [ ] Reject + log regret letter flow
- [ ] Accessible form defaults
- [ ] Empty/error/loading states

---

## 14. Related documents

- [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)
- [PRODUCT_REQUIREMENTS.md](./PRODUCT_REQUIREMENTS.md)
- [RECRUITMENT_WORKFLOW.md](./RECRUITMENT_WORKFLOW.md)
- [USER_ROLES.md](./USER_ROLES.md)
- [ROADMAP.md](./ROADMAP.md)
