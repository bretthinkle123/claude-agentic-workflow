#!/usr/bin/env bash
# Publish the portable pipeline from this repo (the source of truth) to the live
# user-level Claude Code location, ~/.claude/. After this runs, the pipeline's
# agents, hooks, and skills are available in EVERY repo with no per-project copy.
#
# What gets published:
#   global-agents/      -> ~/.claude/agents/              (9 pipeline subagents, incl. conditional design-spec)
#   global-hooks/       -> ~/.claude/hooks/               (deterministic gate scripts, chmod +x)
#   global-skills/      -> ~/.claude/skills/              (17 global skills)
#   templates/          -> ~/.claude/pipeline-templates/  (CLAUDE.md, settings, state seed, mcp.json)
#   global-project-skills/ -> ~/.claude/pipeline-templates/project-skills/  (8 per-project skill templates)
#   scripts/bootstrap-project.sh -> ~/.claude/pipeline-templates/bootstrap-project.sh
#   scripts/run-log-digest.sh    -> ~/.claude/pipeline-templates/run-log-digest.sh  (operator digest)
#
# Per-project setup is then a single command run from inside any repo:
#   bash ~/.claude/pipeline-templates/bootstrap-project.sh
#
# Usage:
#   ./scripts/install-global.sh            # publish (aborts if it would overwrite
#                                          #  pre-existing, DIFFERENT files in ~/.claude)
#   ./scripts/install-global.sh dry-run    # show what would change + any collisions
#   ./scripts/install-global.sh --force    # publish even over colliding files
#
# Idempotent: safe to re-run. Re-publishing the pipeline's own files is fine (they
# match and are not flagged). COLLISION GUARD: if a destination file already exists
# with DIFFERENT content (e.g. another user's own ~/.claude/agents/security.md), the
# install aborts and lists the conflicts rather than silently clobbering them — pass
# --force to overwrite. Files removed from the repo are NOT deleted from ~/.claude.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_HOME="${HOME}/.claude"
TEMPLATES_DEST="${CLAUDE_HOME}/pipeline-templates"
MANIFEST="${CLAUDE_HOME}/.pipeline-install-manifest"   # files this script previously installed
DRY_RUN=false
FORCE=false

case "${1:-}" in
  dry-run)        DRY_RUN=true; echo "[dry-run] No files will be written." ;;
  --force|force)  FORCE=true ;;
  "")             : ;;
  *)              echo "Unknown argument: $1 (use: dry-run | --force)" >&2; exit 2 ;;
esac

# True if $1 (a CLAUDE_HOME-relative path) was recorded as installed by a prior run.
# Our own previously-published files are NOT collisions, so re-publishing edits is
# always clean; only FOREIGN files (never installed by us) trigger the guard.
owned() { [[ -f "$MANIFEST" ]] && grep -qxF "$1" "$MANIFEST"; }

# Print, one per line, every file under $1 (src) that would OVERWRITE a
# different-content file at the matching path under $2 (dest) that we did NOT
# install ourselves. Identical files and our own prior installs are not collisions.
scan_collisions() {
  local src="$1" dest="$2" rel key
  [[ -d "$src" ]] || return 0
  while IFS= read -r rel; do
    rel="${rel#./}"
    key="${dest#"$CLAUDE_HOME"/}/$rel"
    if [[ -f "$dest/$rel" ]] && ! cmp -s "$src/$rel" "$dest/$rel" && ! owned "$key"; then
      echo "  ${dest#"$HOME"/}/$rel"
    fi
  done < <( cd "$src" && find . -type f -print )
}

# Gather collisions across every published tree + the standalone bootstrap script.
COLLISIONS="$(
  scan_collisions "${REPO_ROOT}/global-agents"         "${CLAUDE_HOME}/agents"
  scan_collisions "${REPO_ROOT}/global-hooks"          "${CLAUDE_HOME}/hooks"
  scan_collisions "${REPO_ROOT}/global-skills"         "${CLAUDE_HOME}/skills"
  scan_collisions "${REPO_ROOT}/templates"             "${TEMPLATES_DEST}"
  scan_collisions "${REPO_ROOT}/global-project-skills" "${TEMPLATES_DEST}/project-skills"
  if [[ -f "${TEMPLATES_DEST}/bootstrap-project.sh" ]] && \
     ! cmp -s "${REPO_ROOT}/scripts/bootstrap-project.sh" "${TEMPLATES_DEST}/bootstrap-project.sh" && \
     ! owned "pipeline-templates/bootstrap-project.sh"; then
    echo "  ${TEMPLATES_DEST#"$HOME"/}/bootstrap-project.sh"
  fi
  if [[ -f "${TEMPLATES_DEST}/run-log-digest.sh" ]] && \
     ! cmp -s "${REPO_ROOT}/scripts/run-log-digest.sh" "${TEMPLATES_DEST}/run-log-digest.sh" && \
     ! owned "pipeline-templates/run-log-digest.sh"; then
    echo "  ${TEMPLATES_DEST#"$HOME"/}/run-log-digest.sh"
  fi
)"

if [[ -n "$COLLISIONS" ]]; then
  echo "These existing files in ~/.claude differ from the repo and WOULD be overwritten:" >&2
  echo "$COLLISIONS" >&2
  if [[ "$DRY_RUN" == false && "$FORCE" == false ]]; then
    echo "Aborting to avoid clobbering them. Re-run with --force to overwrite, or back them up first." >&2
    exit 3
  fi
fi

# source-dir -> dest-dir pairs for the three runtime categories
publish_tree() {
  local src="$1" dest="$2" label="$3"
  if [[ ! -d "$src" ]]; then
    echo "Error: $label source not found at $src" >&2
    exit 1
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo "  [$label] $src -> $dest"
    return
  fi
  mkdir -p "$dest"
  cp -r "$src/." "$dest/"
  # A repo README is documentation, not a runtime artifact: drop the tree-root
  # README.md so it never lands in ~/.claude/skills/ etc. (skill/agent READMEs that
  # live INSIDE a subdirectory are untouched — only the top-level one is removed).
  rm -f "$dest/README.md"
}

publish_tree "${REPO_ROOT}/global-agents" "${CLAUDE_HOME}/agents" "agents"
publish_tree "${REPO_ROOT}/global-hooks"  "${CLAUDE_HOME}/hooks"  "hooks"
publish_tree "${REPO_ROOT}/global-skills" "${CLAUDE_HOME}/skills" "skills"

# Templates toolkit (read by bootstrap-project.sh from the installed location)
publish_tree "${REPO_ROOT}/templates" "${TEMPLATES_DEST}" "templates"
publish_tree "${REPO_ROOT}/global-project-skills" "${TEMPLATES_DEST}/project-skills" "project-skills"

if [[ "$DRY_RUN" == false ]]; then
  cp "${REPO_ROOT}/scripts/bootstrap-project.sh" "${TEMPLATES_DEST}/bootstrap-project.sh"
  cp "${REPO_ROOT}/scripts/run-log-digest.sh"    "${TEMPLATES_DEST}/run-log-digest.sh"
  cp "${REPO_ROOT}/scripts/run-summary.sh"       "${TEMPLATES_DEST}/run-summary.sh"
  # Hooks and the operator scripts must be executable when invoked directly.
  chmod +x "${CLAUDE_HOME}/hooks/"*.sh "${TEMPLATES_DEST}/bootstrap-project.sh" \
    "${TEMPLATES_DEST}/run-log-digest.sh" "${TEMPLATES_DEST}/run-summary.sh" 2>/dev/null || true

  # Record everything we just installed (CLAUDE_HOME-relative) so the next run's
  # collision guard recognizes these as ours and never false-flags a re-publish.
  record_tree() {
    local dest="$1" rel
    [[ -d "$dest" ]] || return 0
    ( cd "$dest" && find . -type f -print ) | while IFS= read -r rel; do
      echo "${dest#"$CLAUDE_HOME"/}/${rel#./}"
    done
  }
  {
    record_tree "${CLAUDE_HOME}/agents"
    record_tree "${CLAUDE_HOME}/hooks"
    record_tree "${CLAUDE_HOME}/skills"
    record_tree "${TEMPLATES_DEST}"
  } | sort -u > "$MANIFEST"

  echo "Done. Published agents, hooks, skills, and templates -> ${CLAUDE_HOME}"
  echo "Bootstrap a new project with:"
  echo "    bash ${TEMPLATES_DEST}/bootstrap-project.sh"
  echo "Restart Claude Code (or start a new session) so it picks up the changes."
else
  echo "  [bootstrap] ${REPO_ROOT}/scripts/bootstrap-project.sh -> ${TEMPLATES_DEST}/bootstrap-project.sh"
  echo "  [digest]    ${REPO_ROOT}/scripts/run-log-digest.sh -> ${TEMPLATES_DEST}/run-log-digest.sh"
fi
