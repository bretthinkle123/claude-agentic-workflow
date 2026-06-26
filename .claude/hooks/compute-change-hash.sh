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
{ git diff HEAD 2>/dev/null; git ls-files --others --exclude-standard | sort | xargs -r cat; } | sha256sum | awk '{print $1}'
