#!/usr/bin/env bash
# portability.sh — proves every shipped shell script can actually RUN on macOS.
#
# Why this suite exists: macOS ships bash 3.2 at /bin/bash (Apple will not ship a
# GPLv3 bash) and SIP forbids replacing it. A script that hardcodes `#!/bin/bash`
# AND uses a bash-4+ builtin therefore dies on macOS with a bare
# "mapfile: command not found" — and `PATH` cannot rescue it, because a shebang
# names an interpreter by absolute path, not by lookup.
#
# That combination cost a real run: on 2026-08-24 three hooks (asvs-sast,
# guard-tree-hygiene, check-doc-identifiers) used `mapfile` under `#!/bin/bash`
# and broke the whole pipeline on the operator's Mac. The fix was one character
# class — `#!/usr/bin/env bash` — but it then sat UNCOMMITTED in that machine's
# clone for seven weeks, because nothing in the repo could notice it was missing.
# This suite is that missing noticer.
#
# Two independent checks, because either alone has a hole:
#   1. shebang    — every *.sh uses `#!/usr/bin/env bash`, so PATH decides and a
#                   homebrew bash 5 wins on macOS. Catches the bug BEFORE anyone
#                   adds a bash-4 builtin to the file.
#   2. bash-4-ism — no *.sh uses a bash-4+ builtin under a non-portable shebang.
#                   Catches it the other way round, if check 1 is ever relaxed.
#
# Check 1 is the strict one on purpose: `#!/usr/bin/env bash` is strictly more
# portable than `#!/bin/bash` with no behavioural downside on Linux, so there is
# no legitimate reason for a new script to use the latter.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

echo "-- portability (macOS bash 3.2) --"

cd "$REPO_ROOT" || exit 2

# Every tracked *.sh, excluding .git. Uses `find` rather than `git ls-files` so an
# untracked-but-present script is still checked (a suite should not be fooled by
# staging state).
ALL_SH="$(find . -name '*.sh' -not -path './.git/*' | sort)"

# --- check 1: no hardcoded #!/bin/bash --------------------------------------------
offenders="$(printf '%s\n' "$ALL_SH" | while read -r f; do
  [ -n "$f" ] || continue
  head -1 "$f" | grep -q '^#!/bin/bash$' && printf '%s ' "$f"
done)"
assert_eq "" "$offenders" "no *.sh hardcodes #!/bin/bash (macOS = bash 3.2)"

# --- check 2: no bash-4+ builtin under a non-portable shebang ----------------------
# `mapfile`/`readarray`/`coproc`, associative arrays, and ${var^^}/${var,,} case
# conversion are all bash 4+. Matched only as whole words / real syntax so a grep
# ERE that merely CONTAINS these characters is not a false positive.
BASH4_RE='(^|[^[:alnum:]_])(mapfile|readarray|coproc)[[:space:]]|declare[[:space:]]+-[A-Za-z]*A[[:space:]]|local[[:space:]]+-[A-Za-z]*A[[:space:]]|\$\{[A-Za-z_][A-Za-z0-9_]*(\^\^|,,)'
risky="$(printf '%s\n' "$ALL_SH" | while read -r f; do
  [ -n "$f" ] || continue
  head -1 "$f" | grep -q '^#!/usr/bin/env bash$' && continue   # portable: bash 4+ is fine
  grep -qE "$BASH4_RE" "$f" && printf '%s ' "$f"
done)"
assert_eq "" "$risky" "no bash-4+ builtin under a non-portable shebang"

# --- check 3: the three hooks that actually broke stay portable --------------------
# Named explicitly so a careless bulk edit cannot silently re-break the exact files
# that cost the 2026-08-24 run, even if someone loosens the checks above.
for h in asvs-sast guard-tree-hygiene check-doc-identifiers; do
  assert_eq "#!/usr/bin/env bash" "$(head -1 "$HOOKS/$h.sh")" "$h.sh keeps the portable shebang"
done

# --- check 4: every *.sh is syntactically valid ------------------------------------
# Cheap, and it means this suite fails loudly on a truncated or corrupted script
# rather than only on a shebang nit.
bad_syntax="$(printf '%s\n' "$ALL_SH" | while read -r f; do
  [ -n "$f" ] || continue
  bash -n "$f" 2>/dev/null || printf '%s ' "$f"
done)"
assert_eq "" "$bad_syntax" "every *.sh parses (bash -n)"

finish portability
