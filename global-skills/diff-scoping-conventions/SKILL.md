---
name: diff-scoping-conventions
description: Shared working-tree change-set logic so security and testing scope to the same files, plus the change-set hash that testing records as tested_change_hash and documentation records as reviewed_change_hash.
---

# Diff-scoping conventions

Security and testing must scope to **exactly the same change set** so their
findings line up and neither scans the whole repo on every loop. This is the
single highest-leverage token lever in the pipeline.

## The change set

The change set is the uncommitted work in the working tree since the last commit:

```
tracked changes   : git diff HEAD --name-only
UNION
untracked files   : git ls-files --others --exclude-standard
```

- **Untracked files MUST be included.** New modules and test files are untracked
  until the deployment agent's single commit, and `git diff HEAD` alone silently
  misses them. Always union the two lists.
- **No-HEAD case (empty repo, first run only):** if there are no commits yet
  (`git rev-parse --verify HEAD` fails), there is no baseline to diff against —
  scan the **full project**. This happens only on the very first greenfield run.
- **There is no `last_clean_commit` pointer.** Every commit is already a clean
  baseline because the deployment agent is the only thing that commits. Diff
  against `HEAD`, nothing else.

Every agent that scopes a change computes the set with this identical logic.

## Fields both security and testing record

- `scope`: `"diff"` (normal) or `"full"` (no-HEAD first run).
- `since_commit`: the `HEAD` hash the diff was measured against, or `null` on a
  full first scan.

## The change-set hash

The hash is a SHA-256 over the diff plus the contents of every untracked file:

```bash
{ git diff HEAD; git ls-files --others --exclude-standard | sort | xargs -r cat; } | sha256sum | awk '{print $1}'
```

Two agents record this hash, for two different purposes:

- **testing** writes it as `tested_change_hash` in `test-results.json` — its
  record of exactly what the test run covered.
- **documentation** writes it as `reviewed_change_hash` in
  `.pipeline/review-manifest.json`, computed **last**, after every README and
  `system_architecture.md` edit. This is the deployment gate's **currency
  anchor** — because documentation edits the tree after testing runs, its hash
  (not testing's) is what the commit must match.

Use the command verbatim everywhere so the deployment gate's recompute matches
byte-for-byte. On a no-HEAD repo, `git diff HEAD` produces nothing on both sides,
so the hashes still agree.
