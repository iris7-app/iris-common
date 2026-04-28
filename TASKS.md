# TASKS — iris-common

Open work only. Per `~/.claude/CLAUDE.md` rules : universal
cross-repo conventions (release scripts, ADR drift tooling,
Conventional Commits CI template, Renovate base) only.

Created 2026-04-28 to capture the **Iris rebrand** scope on the
common layer.

---

## 🌀 IRIS REBRAND (in flight 2026-04-28)

Coordinated rename Iris → Iris. See full context + phases in
[Java TASKS.md](https://gitlab.com/iris-7/iris-service-java/-/blob/main/TASKS.md#-iris-rebrand-in-flight-2026-04-28).

Common-side scope :

- **Code-level** : 23 files, 208 refs to "mirador". Affects :
  - ADR cross-references in `docs/adr/` (ADR-0001 / 0057 / 0060 /
    0061 / 0063 all reference "Iris" or "iris-7")
  - `bin/ship/*` scripts that hardcode `iris-7` GitLab group
  - `renovate-base.json` if it references project names
  - `ci-templates/conventional-commits.yml` if it has project hints
  - The flat ADR index `docs/adr/README.md`
- **Phase 4 (code rename)** : light ; 23 files is a small surface,
  doable in a dedicated session in ~30-60 min.

### ✅ Decisions verrouillées

Same as the master rebrand record (see Java TASKS.md). Visual
locked = `02o-iris-final.svg`. Tagline = `7 FACETS`.

---

## 🟡 Stability-check ADR drift (resolved 2026-04-28)

Java-side stability-check 2026-04-28 surfaced ADR flat-index drift
in iris-service-java ; resolved by `infra/common/bin/dev/regen-adr-index.sh --in-place`
([!248](https://gitlab.com/iris-7/iris-service-java/-/merge_requests/248)).

The same regen script applies to iris-common itself if its own
`docs/adr/README.md` drifts ; cron-checking it is a future
nice-to-have but not in scope today.
