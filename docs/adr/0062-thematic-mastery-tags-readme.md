# 0062. Thematic mastery axes — tag annotations + README top blocks

Date: 2026-04-27
Status: Accepted

## Context

The mirador1 polyrepo (mirador-service-java + mirador-service-python +
mirador-ui + mirador-service-shared + mirador-common) is portfolio-
themed — recruiters and architects browsing the repos for 30 seconds
form a first impression from the README and the most recent
`stable-v*` tag annotation.

Two pain points emerged in the 2026-04-27 session :

1. **Stable tag annotations were 1-line strings** ("Stability checkpoint
   — MCP foundation + grype CVE fix"). Reading the tag later, you
   could not tell whether the new MCP tools were actually invoked
   end-to-end, whether mobile responsive checks were done, whether
   the SLO chaos demo actually fired. The tag was an assertion, not
   a verified record.
2. **README tops jumped straight into the project description**, with
   no scannable summary of what the project DEMONSTRATES — recruiters
   had to read 3 paragraphs to understand the central themes the
   project covers.

Both gaps were filled by user directives during the session :
- "À chaque fois que versionne j'aimerais que tu passes un test un peu
  complet et que tu formalises dans la version ce que tu as réellement
  vérifié même si c'est long" (recurring tag annotation rule).
- "Le rapport de texte devra contenir des sections : IA, sécurité,
  fonctionnel, infra cloud, etc montrant un accomplissement autour
  des thèmes centraux de l'informatique actuelle et liés aux enjeux
  à maîtriser" (thematic axes).
- "Il faudra le mettre en avant au début du readme" (mirror at top
  of README).

## Decision

Every `stable-v*` (and `stable-py-v*`, `stable-vN.N.N`-prefixed) tag
annotation carries TWO blocks beyond the bare-bones "what changed" :

1. **`## Verified`** — the audit trail : CI pipeline IDs + statuses,
   local test pass results, manual probe outcomes, regression check
   vs the previous tag's known limitations. Sections explicitly mark
   genuinely-N/A steps as `⏭ <step> — N/A because <reason>` rather
   than silently omitting them.
2. **`## Themes maîtrisés`** — accomplishments per central IT axis.
   10 axes (skip Frontend on backend repos and vice versa) :

   - 🤖 **IA** — LLM integration, MCP tooling, AI Observability.
   - 🔒 **Sécurité** — AuthN/AuthZ surfaces, CVE posture, headers,
     filters.
   - 🧠 **Fonctionnel** — domain features end-to-end, invariants,
     property tests.
   - ☁️ **Infrastructure & Cloud** — IaC, deploy targets, cost
     discipline.
   - 📊 **Observabilité** — SLO/SLA, OTel, dashboards, alerts,
     runbooks.
   - ✅ **Qualité** — coverage, mutation, sonar, lints, test pyramid.
   - 🔄 **CI/CD** — pipeline stages, compat matrix, release engineering.
   - 🏛 **Architecture** — ADRs accepted/amended, patterns enforced,
     hygiene status.
   - 🎨 **Frontend** — UI repos only.
   - 🛠 **DevX** — tooling improvements, onboarding-friction wins.

The same 10 axes appear at the **TOP** of every portfolio-facing
README (`mirador-service-java`, `mirador-service-python`,
`mirador-ui`) as a `> What this project demonstrates mastery of`
blockquote — sitting ABOVE the badges, ABOVE the project description.
Each bullet is dense with the project's actual specifics (not generic
claims).

The TAG ANNOTATION is the source of truth (audit trail of the
journey). The README block is the latest snapshot of accumulated
mastery (the destination). They drift fast — update the README
bullet whenever a new tag annotation moves the corresponding axis
forward.

Skipped on infrastructure-only repos (`mirador-common`,
`mirador-service-shared`) — they are not standalone portfolio
pieces ; their READMEs focus on "what's inside + how to consume".

## Why these 10 axes ?

They cover the central themes a senior backend / full-stack engineer
must master in 2026 :

- **IA** — moved from "research / FAANG-only" to mainstream backend
  responsibility (Spring AI, LLM integration, MCP servers, agentic
  workflows).
- **Sécurité** — non-negotiable, scope expanded with supply-chain
  (CVEs, SBOM, signing) on top of classic AuthN/AuthZ.
- **Fonctionnel** — the domain itself, what value the system
  delivers.
- **Infrastructure & Cloud** — multi-cloud literacy + IaC are
  table-stakes ; cost discipline is increasingly scrutinized.
- **Observabilité** — three-pillars (logs, metrics, traces) +
  SLO/SLA culture is what separates "ops" from "SRE".
- **Qualité** — test pyramid + static analysis + mutation testing
  prove the team values shipping the right thing twice.
- **CI/CD** — pipeline-as-code + Conventional Commits + auto-merge
  is the modern release engineering baseline.
- **Architecture** — ADRs as historical record, patterns as
  binding constraints, hygiene rules as tech-debt prevention.
- **Frontend** — for UI repos, the modern paradigms (zoneless,
  signals, mobile-first).
- **DevX** — Renovate + Lefthook + scripted gates +
  onboarding-friction wins ; reflects how the team values future
  contributors and future selves.

## Consequences

**Positive** :
- Tag annotations become an auditable history. `git show
  stable-vX.Y.Z` answers "what does this checkpoint guarantee?"
  in one read, no chasing pipeline IDs or audit reports.
- README tops give a recruiter a 30-second read that surfaces
  central IT mastery themes before they invest deeper time.
- The 10 axes act as a checklist : a tag missing an axis (e.g.
  no `🔒 Sécurité` section) prompts a "did we forget to verify
  the security posture this rev?" question.
- Drift between tag annotations and README block is a useful
  signal : tag writes are forced (every release) while README
  writes are explicit, so a stale README block visible against
  fresh tag annotations is easy to spot.

**Negative** :
- Tag annotations become long (~100 LOC). The user's explicit
  framing — "même si c'est long" — accepts this trade-off : the
  audit trail is more valuable than scrollability.
- Every tag now requires a manual verification pass. This is
  opt-in vs CI-only-green tagging ; the rule's enforcement
  depends on the engineer (or the `~/.claude/CLAUDE.md`-driven
  Claude session) actually running through the recipe.
- Initial setup cost : every README needs a one-time block
  insertion — done in 3 MRs (java !230, python !32, ui !168) on
  2026-04-27.

**Neutral** :
- The 10-axis taxonomy is opinionated. Other valid taxonomies
  exist (e.g. CDMC competency model, IEEE SE BoK). We picked
  these 10 because they map directly onto the portfolio review
  questions a hiring manager asks ("Show me the AI work. Show me
  the security posture. Show me how you track SLOs").

## Operational reference

The full rule text lives in `~/.claude/CLAUDE.md` (global Claude
instructions) under three sections :

1. "Tag every green stability checkpoint, never tag on red"
   (existing — when to tag).
2. "Tag annotations document what was verified — formalise
   everything" (new 2026-04-27 — what to write in the
   annotation, including the 10 axes).
3. "Surface the same themes at the TOP of the README" (new
   2026-04-27 — mirror block in the README).

The 10-axis taxonomy + recipe per stack live there ; this ADR is the
WHY + the cross-repo binding decision.

## Examples

Two reference tags shipped on 2026-04-27 with the new format :
- [`stable-v1.2.10`](https://gitlab.com/mirador1/mirador-service-java/-/tags/stable-v1.2.10)
  (Java) — Spring AI streamable-http + Javadoc fix.
- [`stable-py-v0.6.9`](https://gitlab.com/mirador1/mirador-service-python/-/tags/stable-py-v0.6.9)
  (Python) — X-API-Key middleware (parity with Java).

Both tag annotations show the full Verified + Themes maîtrisés blocks.

## References

- [`~/.claude/CLAUDE.md`](file:///Users/benoitbesson/.claude/CLAUDE.md)
  → "Tag annotations document what was verified" + "Surface the same
  themes at the TOP of the README".
- [common ADR-0061](0061-per-repo-tag-namespace-pattern.md) — the
  per-repo `stable-v` / `stable-py-v` prefix pattern that this
  rule layers on top of.
- 2026-04-27 session transcript — the discussion that drove this
  decision.
