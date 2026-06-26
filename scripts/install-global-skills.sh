#!/usr/bin/env bash
# Install (or update) global Claude Code skills from the repo into ~/.claude/skills/.
#
# Convention: global-skills/ is the source of truth — edit skills there, then
# re-run this script to publish the change to the live location.
#
# Usage:
#   ./scripts/install-global-skills.sh            # install all skills
#   ./scripts/install-global-skills.sh dry-run    # show what would change, copy nothing
#
# Idempotent: safe to re-run. New files are added, existing files are overwritten,
# skills removed from global-skills/ are NOT deleted from ~/.claude/skills/ (manual
# cleanup intentional — avoids surprises when running on a shared machine).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${REPO_ROOT}/global-skills"
DEST="${HOME}/.claude/skills"
DRY_RUN=false

if [[ "${1:-}" == "dry-run" ]]; then
  DRY_RUN=true
  echo "[dry-run] No files will be written."
fi

if [[ ! -d "$SRC" ]]; then
  echo "Error: global-skills/ not found at $SRC" >&2
  exit 1
fi

mkdir -p "$DEST"

INSTALLED=0
UPDATED=0

for skill_dir in "$SRC"/*/; do
  name="$(basename "$skill_dir")"
  target_dir="${DEST}/${name}"

  if [[ "$DRY_RUN" == true ]]; then
    if [[ -d "$target_dir" ]]; then
      echo "  [update] $name"
    else
      echo "  [new]    $name"
    fi
    continue
  fi

  if [[ -d "$target_dir" ]]; then
    cp -r "$skill_dir/." "$target_dir/"
    UPDATED=$((UPDATED + 1))
  else
    cp -r "$skill_dir" "$target_dir"
    INSTALLED=$((INSTALLED + 1))
  fi
done

if [[ "$DRY_RUN" == false ]]; then
  echo "Done. Installed: $INSTALLED new, $UPDATED updated → $DEST"
  echo "Restart Claude Code (or start a new session) to pick up changes."
fi
