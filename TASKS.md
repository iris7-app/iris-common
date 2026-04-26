# Tasks — `mirador-common`

Open work only. Per `~/.claude/CLAUDE.md` rules : universal cross-repo
items only ; per-repo items live in each consumer's own `TASKS.md`.

---

## 🔧 bump-common-everywhere.sh — finishing touches

The script SHIPPED on 2026-04-26 (commit [`737ca08`](https://gitlab.com/mirador1/mirador-common/-/commit/737ca08))
and was **smoke-tested end-to-end on 2026-04-26 15:28** :

✅ Pre-flight checks (common sync state + per-consumer state) passed.
✅ Bumped 3 lagging consumers (shared, python, ui) from `4005e51` → `3e7acba`.
✅ Java correctly skipped (already at target SHA).
✅ MRs auto-created + auto-merge armed for python ([!25](https://gitlab.com/mirador1/mirador-service-python/-/merge_requests/25))
   and ui ([!156](https://gitlab.com/mirador1/mirador-ui/-/merge_requests/156)).
✅ Pre-push hooks (vitest + ng build for ui) pass cleanly through the script.

### Doc polish

✅ All shipped 2026-04-26 15:33 :
- `README.md` "What lives here" table : new row for `bump-common-everywhere.sh`.
- `README.md` "How to update" section : bulk-bump command + `--dry-run` example.
- (`bin/README.md` not created — script self-documents via `--help` and the table at root README is canonical.)

No further open work. File can be deleted at next session start if no new tasks land.
