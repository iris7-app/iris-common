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

### Doc polish (open)

☐ **Document in `bin/README.md`** : add a row in the `ship/` table for
`bump-common-everywhere.sh` describing it (cross-repo bulk SHA bump).

☐ **Mention in main `README.md`** : 1-line mention in the "How to update"
section : "to propagate a common change to all 4 consumers in one
command, see `bin/ship/bump-common-everywhere.sh`".
