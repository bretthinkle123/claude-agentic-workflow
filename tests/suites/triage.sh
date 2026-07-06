#!/usr/bin/env bash
# triage.sh — structural guards for the read-only triage agent (PR O).
# The triage agent ingests UNTRUSTED production telemetry, so its safety rests on TOOL ABSENCE
# (no Bash/Edit → nothing to execute an injected instruction into or modify) plus the global
# marker deny (its Write can't forge an approval). These are deterministic, file-level
# invariants — this suite fails LOUD if a future edit weakens any of them.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../helpers/assert.sh"

AGENT="$REPO_ROOT/global-agents/triage.md"
SKILL="$REPO_ROOT/global-skills/triage-conventions/SKILL.md"
SETTINGS="$REPO_ROOT/templates/project-settings.json"
MCP="$REPO_ROOT/templates/mcp.json"
echo "-- triage (read-only incident agent) --"

# The frontmatter tools: line (first 'tools:' in the file).
TOOLS_LINE="$(grep -m1 '^tools:' "$AGENT")"

# (1) the agent exists and declares the expected identity
assert_eq "true" "$([ -f "$AGENT" ] && echo true)"                       "triage.md exists"
assert_eq "true" "$(grep -qE '^name: triage$' "$AGENT" && echo true)"    "declares name: triage"
assert_eq "true" "$(grep -qE '^model: opus$' "$AGENT" && echo true)"     "runs on opus (reasoning over noisy telemetry)"

# (2) THE CORE GUARANTEE — bounded by tool ABSENCE. No Bash, no Edit, ever.
assert_eq "" "$(printf '%s' "$TOOLS_LINE" | grep -oE '\bBash\b')"  "tools list contains NO Bash (no exec surface for an injected instruction)"
assert_eq "" "$(printf '%s' "$TOOLS_LINE" | grep -oE '\bEdit\b')"  "tools list contains NO Edit (cannot modify code/config/infra)"
# and it DOES carry exactly the read/write-brief + sentry surface it needs
assert_eq "true" "$(printf '%s' "$TOOLS_LINE" | grep -q '\bRead\b'        && echo true)" "has Read (ground a hypothesis in the repo)"
assert_eq "true" "$(printf '%s' "$TOOLS_LINE" | grep -q '\bWrite\b'       && echo true)" "has Write (the brief)"
assert_eq "true" "$(printf '%s' "$TOOLS_LINE" | grep -q '\bmcp__sentry\b' && echo true)" "has mcp__sentry (the read-only input channel)"

# (3) the untrusted-input posture is stated in the agent (not left implicit)
assert_eq "true" "$(grep -qiE 'untrusted' "$AGENT" && echo true)"           "agent states telemetry is untrusted input"
assert_eq "true" "$(grep -qE 'NOT ACTED ON' "$AGENT" && echo true)"         "agent carries the NOT-ACTED-ON injection rule"
# and it is NOT wired into the pipeline loop (standalone, on-demand)
assert_eq "true" "$(grep -qiE 'NOT (in|part of) the pipeline loop|standalone' "$AGENT" && echo true)" "agent declares it is out-of-loop / standalone"

# (4) the settings marker deny covers triage's only forgery vector (its Write)
for m in plan diff design; do
  assert_eq "true" "$(grep -qE "Write\\(\\*\\*/\\.pipeline/${m}-approved\\)" "$SETTINGS" && echo true)" "settings deny Write on ${m}-approved (blocks triage self-approval)"
done
assert_eq "true" "$(grep -qE 'Write\(\*\*/\.pipeline/waivers\.json\)' "$SETTINGS" && echo true)" "settings deny Write on waivers.json"

# (5) the skill documents the schema, redaction, and injection report; MCP is read-only-scoped
assert_eq "true" "$([ -f "$SKILL" ] && echo true)"                          "triage-conventions skill exists"
assert_eq "true" "$(grep -qiE 'REDACTED' "$SKILL" && echo true)"            "skill carries the redaction rule (brief != second leak)"
assert_eq "true" "$(grep -qiE 'injection report' "$SKILL" && echo true)"    "skill defines the injection report"
assert_eq "true" "$(grep -qiE 'read-only' "$SKILL" && echo true)"           "skill's MCP checklist mandates a read-only token"
assert_eq "true" "$(grep -qE 'incident-brief\.md' "$SKILL" && echo true)"   "skill names the .pipeline/incident-brief.md output"

# (6) the Sentry MCP server is present in the template (project-scoped; inert until wired)
assert_eq "true" "$(grep -qE '\"sentry\"' "$MCP" && echo true)"             "templates/mcp.json carries the sentry server entry"

finish triage
