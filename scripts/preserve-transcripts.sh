#!/usr/bin/env bash
# preserve-transcripts.sh — copy every subagent transcript from the Claude Code session
# store into a run-evidence directory, with integrity asserts (F-M4-7 / M4-tel4).
#
# WHY THIS EXISTS: M4's preservation grepped the parent session JSONL by agentId — which
# only captures agents whose sidechain lines happen to be inlined there — and silently
# produced 14 empty .output files (planning, plan-audit, both cycle-3 re-runs among them).
# The real per-agent traces live in the session store:
#   <session-dir>/subagents/agent-<id>.jsonl   (full sidechain trace per named agent)
#   <session-dir>/tool-results/<id>.txt        (task text results, e.g. finder outputs)
# This script copies BOTH, refuses to preserve an empty file, flags byte-identical pairs
# (the M4 pair b79on0wti≡bl2q7axu7 was identical AT SOURCE — flag, not fail), and writes
# a sha256 MANIFEST so a later audit can verify nothing was altered.
#
# Usage:
#   preserve-transcripts.sh <dest-dir> [session-dir] [since]
#     dest-dir    : where .output copies land (e.g. <engine>/examples/<app>/run-evidence/<run>/transcripts)
#     session-dir : optional explicit path to the session directory (the one containing
#                   subagents/). Default: the most recently modified session under
#                   ~/.claude/projects/<encoded-cwd>/ that has a subagents/ dir.
#     since       : optional run-start filter (epoch seconds, or a file whose mtime is the
#                   run start, e.g. .pipeline/state.json). F-M4′-7: a standing session's
#                   store is CUMULATIVE across runs — M4′'s preservation swept 23 M4-era
#                   transcripts into the M4′ evidence set. With `since`, only agent files
#                   modified at/after the run start are copied; the manifest records each
#                   file's mtime either way so provenance is auditable.
# Exit codes: 0 ok; 1 integrity failure (empty/missing transcript); 2 usage/environment.
set -uo pipefail

DEST="${1:?usage: preserve-transcripts.sh <dest-dir> [session-dir] [since]}"
SESSION="${2:-}"
SINCE_RAW="${3:-}"
SINCE=0
if [ -n "$SINCE_RAW" ]; then
  if [ -f "$SINCE_RAW" ]; then SINCE=$(stat -c %Y "$SINCE_RAW" 2>/dev/null || echo 0)
  else SINCE="$SINCE_RAW"; fi
  case "$SINCE" in ''|*[!0-9]*) echo "[preserve-transcripts] bad 'since' value: $SINCE_RAW" >&2; exit 2 ;; esac
fi

# F-M4′-7 usability: fail loudly when this clearly isn't the pipeline project's repo —
# run from the engine repo, the CWD-derived lookup silently found nothing in M4′.
if [ -z "$SESSION" ] && [ ! -f .pipeline/state.json ]; then
  echo "[preserve-transcripts] CWD has no .pipeline/state.json — this doesn't look like the" >&2
  echo "                       pipeline project's repo. Run from the throwaway/app repo, or" >&2
  echo "                       pass the session dir explicitly as arg 2." >&2
  exit 2
fi

# --- locate the session dir when not given -----------------------------------------
if [ -z "$SESSION" ]; then
  # Claude Code encodes the project cwd into a directory name by replacing every
  # non-alphanumeric character with '-'. pwd -W yields the Windows form on Git Bash.
  RAW="$(pwd -W 2>/dev/null || pwd)"
  ENC="$(printf '%s' "$RAW" | sed 's|[^A-Za-z0-9]|-|g')"
  PROJ=""
  for cand in "$HOME/.claude/projects/$ENC" \
              "$HOME/.claude/projects/$(printf '%s' "$ENC" | sed 's/^\(.\)/\l\1/')"; do
    [ -d "$cand" ] && PROJ="$cand" && break
  done
  if [ -z "$PROJ" ]; then
    echo "[preserve-transcripts] no project dir found for cwd ($ENC) under ~/.claude/projects/" >&2
    echo "                       pass the session dir explicitly as arg 2." >&2
    exit 2
  fi
  SESSION="$(ls -dt "$PROJ"/*/ 2>/dev/null | while read -r d; do
    [ -d "$d/subagents" ] && echo "$d" && break
  done)"
  if [ -z "$SESSION" ]; then
    echo "[preserve-transcripts] no session with a subagents/ dir under $PROJ" >&2
    exit 2
  fi
fi
SESSION="${SESSION%/}"
[ -d "$SESSION/subagents" ] || { echo "[preserve-transcripts] $SESSION has no subagents/ dir" >&2; exit 2; }

mkdir -p "$DEST"
FAIL=0
COPIED=0

copy_one() {  # $1 = source file, $2 = dest basename (without .output)
  local src="$1" base="$2" out="$DEST/$2.output"
  if [ ! -s "$src" ]; then
    echo "[preserve-transcripts] EMPTY SOURCE (refusing to preserve silence): $src" >&2
    FAIL=1
    return
  fi
  cp -p "$src" "$out"   # -p: keep the source mtime — the manifest's provenance column
  if [ ! -s "$out" ]; then
    echo "[preserve-transcripts] copy produced an empty file: $out" >&2
    FAIL=1
    return
  fi
  COPIED=$((COPIED + 1))
}

in_window() {  # $1 = file → 0 if at/after SINCE (or no filter)
  [ "$SINCE" -eq 0 ] && return 0
  local m; m=$(stat -c %Y "$1" 2>/dev/null || echo 0)
  [ "$m" -ge "$SINCE" ]
}

# Named-agent sidechain traces.
for f in "$SESSION"/subagents/agent-*.jsonl; do
  [ -e "$f" ] || continue
  in_window "$f" || continue
  id="$(basename "$f")"; id="${id#agent-}"; id="${id%.jsonl}"
  copy_one "$f" "$id"
done

# Task text results (finder/verifier outputs fetched via TaskOutput).
if [ -d "$SESSION/tool-results" ]; then
  for f in "$SESSION"/tool-results/*.txt; do
    [ -e "$f" ] || continue
    in_window "$f" || continue
    id="$(basename "$f" .txt)"
    # A named agent id never collides with a task-result id; if it somehow does, the
    # richer sidechain trace wins and the text result is preserved with a suffix.
    if [ -f "$DEST/$id.output" ]; then
      copy_one "$f" "$id.tool-result"
    else
      copy_one "$f" "$id"
    fi
  done
fi

if [ "$COPIED" -eq 0 ]; then
  echo "[preserve-transcripts] nothing copied from $SESSION — wrong session?" >&2
  exit 1
fi

# --- integrity: manifest (sha + source mtime, provenance-auditable) + duplicates -----
( cd "$DEST" && for o in ./*.output; do
    printf '%s  %s  mtime=%s\n' "$(sha256sum "$o" | cut -d' ' -f1)" "$o" "$(stat -c %Y "$o")"
  done | sort -k2 ) > "$DEST/MANIFEST.sha256"

DUPES="$(awk '{print $1}' "$DEST/MANIFEST.sha256" | sort | uniq -d)"
if [ -n "$DUPES" ]; then
  echo "[preserve-transcripts] NOTE — byte-identical transcript pairs (verify at source" >&2
  echo "  whether the platform stored one result under two IDs, as in M4, or content was lost):" >&2
  for h in $DUPES; do
    grep "^$h" "$DEST/MANIFEST.sha256" | awk '{print "    " $2}' >&2
  done
fi

echo "[preserve-transcripts] $COPIED transcripts -> $DEST (manifest: MANIFEST.sha256; session: $SESSION)"
[ "$FAIL" -eq 0 ] || { echo "[preserve-transcripts] INTEGRITY FAILURE — see EMPTY SOURCE lines above." >&2; exit 1; }
exit 0
