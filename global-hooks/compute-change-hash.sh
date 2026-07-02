#!/bin/bash
# Single source of truth for the working-tree change-set hash: a SHA-256 over the
# tracked diff plus the contents of every untracked file (see the
# diff-scoping-conventions skill). Both documentation (via write-review-manifest.sh,
# recorded as reviewed_change_hash) and deployment-gate.sh (the currency recompute)
# call this, so the two hashes agree byte-for-byte. Prints only the hash to stdout.
#
# Deliberately NO `set -e`/`pipefail`: on a greenfield repo `git diff HEAD` exits
# non-zero (no HEAD) and must be tolerated — the hash then covers just the untracked
# tree, exactly as the diff-scoping skill specifies.
#
# Determinism (audit E1): `LC_ALL=C sort -z` makes the untracked-file ordering
# byte-deterministic regardless of the caller's LC_COLLATE, so documentation
# (manifest), approve-diff.sh, and deployment-gate.sh agree on the hash across shells
# with different locales. NUL-delimited (`ls-files -z` / `sort -z` / `xargs -0`) so a
# filename containing a space or newline can't split the `cat` argument list and
# silently change the concatenation (and thus the hash). This is byte-identical to the
# old bare-`sort | xargs` output for ordinary filenames, so it does NOT invalidate any
# previously-approved hash — it only closes the cross-locale / odd-filename divergence.
{ git diff HEAD 2>/dev/null; git ls-files -z --others --exclude-standard | LC_ALL=C sort -z | xargs -0 -r cat; } | sha256sum | awk '{print $1}'
