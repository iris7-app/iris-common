# 0063. MR batching vs fan-out — when to merge, when to split

Date: 2026-04-27
Status: Accepted

## Context

The 2026-04-27 evening session shipped 8 unrelated Java changes
(chaos endpoints, dashboard URI filter, server-side product search,
PUT `/orders/{id}/status`, GET `/products/{id}/orders`, JaCoCo HTML,
smoke flow, sections/code.sh, banner.svg, ChurnControllerTest,
TASKS.md sweep) as **8 separate MRs**. The user pointed out this was
an anti-pattern : 8 × ~15 min of CI cumulé ≈ 2 h wall-time + 2 h
runner CPU, where a single batched MR would have taken ~15 min.

The author had pushed `feat/<concern>` branches one by one as each
unit of work completed, opening one MR per branch. The driving
intuition was "atomic, reviewable units" — but that intuition is
ALREADY served by the per-commit boundary. The MR boundary is for
the CI cycle.

## Decision

**Default: batch on `dev` (or a dedicated batch branch) until the
work is coherent, then ship as ONE MR with N commits.**

The 1-commit-per-concern rule (existing) gives atomicity for
`git revert`, `git log`, `git blame`, and reviewer scanning. The
1-MR-per-batch rule (new explicit) gives a single CI cycle per
session of related work.

### When to ship a separate MR (the exceptions)

- **Genuinely different release tracks** : ship a CVE fix
  immediately on its own MR ; don't wait for the feature batch
  it shares the day with.
- **Branch-protection / review requirements differ** : if one
  change needs the security-sensitive review path and the rest
  don't, splitting avoids gating the rest behind that review.
- **Risky change you want to ring-fence** : first push of a new
  CI image, refactor of a critical job. Keep failure surface
  bounded so the rest of the day's work doesn't roll back with it.
- **Different repos** : one MR per repo always — cross-repo
  consistency is enforced at the human level (PR descriptions
  cross-link), not by GitLab.

### When to batch (the default)

Everything else. If five unrelated greenfield additions all build
locally + each has its own commit + their union doesn't blow up the
review surface (~ 500 LOC diff is the soft ceiling), one MR is the
right call.

### Recovery when the anti-pattern slips through

- Don't try to merge fan-out MRs in queue order — the auto-merge
  cycle compounds wall-time.
- Branch off `main`, cherry-pick each fan-out branch's commits,
  push the consolidated branch, open ONE consolidator MR, close
  the originals as `Superseded by !N`. ≤ 10 min of git work, saves
  hours of CI burn.

## Consequences

### Positive

- 1 CI cycle per coherent batch of work — not N. ~85 % wall-time
  saving in the typical evening-session pattern (5-10 unrelated
  changes).
- Reviewer cognition stays scoped : one MR description summarises
  the day, the per-commit history shows the journey.
- Tag-on-green stays simple : after the batch lands on `main` and
  the post-merge pipeline is green, one tag covers everything.
- Aligns with the existing global CLAUDE.md "Réduire les vagues
  CI" rule. This ADR is the canonical reference for it.

### Negative

- A single failure in the batch's CI fails the WHOLE batch —
  the diff has to be inspected to identify which commit broke it.
  Mitigation : `./mvnw verify` / `npm run build` / `uv run pytest`
  locally between commits catches 80 % of failures BEFORE push.
  The remaining 20 % is recognisable patterns (timeout, runner
  pressure, flaky network) that don't track to a specific commit
  anyway.
- The MR description gets long. Mitigation : a short top-level
  paragraph + an ordered bulleted list with one link per commit's
  scope. The Java [!247](https://gitlab.com/iris-7/iris-service-java/-/merge_requests/247)
  consolidation done on 2026-04-27 is the canonical example to
  copy.

### Neutral

- Auto-merge mechanics work the same on either pattern — `glab
  mr merge --auto-merge` arms `merge_when_pipeline_succeeds=true`
  whether the MR is a fan-out leaf or a consolidator.

## Cross-references

- Existing global rule : `~/.claude/CLAUDE.md` → "Réduire les vagues
  CI — batch the changes per MR". This ADR formalises that rule with
  the exception list + recovery procedure.
- Existing project CLAUDE.md → "Réduire les vagues CI" sections in
  iris-service-java + iris-service-python + iris-ui — they
  reference the global rule. No change needed there.
- 2026-04-27 evening session — 8 fan-out MRs consolidated into
  Java [!247](https://gitlab.com/iris-7/iris-service-java/-/merge_requests/247)
  by cherry-picking the 8 source branches onto a single
  `consolidate/2026-04-27-batch` branch. Saved ~1 h 45 of CI.

## Related

- [common ADR-0001 — Shared repo via submodule](0001-shared-repo-via-submodule.md)
  (where the 4 consumers live)
- [common ADR-0061 — Per-repo tag namespace pattern](0061-per-repo-tag-namespace-pattern.md)
  (tag-on-green still works on the consolidator MR's merge commit)
