# Global Skills

This directory is the **source of truth** for all global Claude Code skills used by the pipeline. Skills are not read from here at runtime — they must be installed to `~/.claude/skills/` where Claude Code resolves them.

> **Standards review — last done 2026-07-09, next due 2027-07.** Skills are static text: the
> security-standards-bearing ones (`data-protection-conventions`, `auth-patterns`,
> `api-edge-conventions`, `secrets-management`, `regulated-data-conventions`,
> `audit-trail-conventions`, `data-lifecycle-conventions`, `stride-threat-model-template`)
> encode OWASP/ASVS/NIST guidance as of when they were written and nothing re-checks them
> automatically. Once a year, re-verify their named mechanisms (KDF choice, cipher modes, TLS
> versions, ASVS numbering, regime requirements) against current guidance and bump this line.

## How it works

Each subdirectory is a skill (`<name>/SKILL.md` plus optional sibling files). Agents reference skills by name in their `skills:` frontmatter; Claude Code reads them from `~/.claude/skills/<name>/` at agent startup. This directory is version-controlled backup only — no runtime token cost.

## Installing / updating skills

Run the install script from the repo root:

```bash
./scripts/install-global.sh
```

Then **restart Claude Code** (or start a new session) so the updated files are picked up.

To preview what would change without writing anything:

```bash
./scripts/install-global.sh dry-run
```

The script is idempotent — safe to re-run at any time. New skills are added, existing ones are overwritten. Skills deleted from this directory are **not** removed from `~/.claude/skills/` automatically (intentional — avoids accidents on shared machines; delete manually if needed).

## Updating a skill

1. Edit `global-skills/<name>/SKILL.md` (or its sibling files) in this repo.
2. Run `./scripts/install-global.sh`.
3. Restart Claude Code.

## Adding a new skill

1. Create `global-skills/<name>/SKILL.md` with `name:` and `description:` frontmatter.
2. Run `./scripts/install-global.sh`.
3. To **preload** it (loaded into an agent at startup), add `<name>` to that agent's `skills:` frontmatter in `.claude/agents/<agent>.md`.
4. To keep it **on-demand** (agent invokes it via the Skill tool when relevant), leave it off the frontmatter list and make sure the `description:` line is specific enough for the model to know when to invoke it.
5. Restart Claude Code.

## On a new machine

```bash
git clone <this-repo>
cd claude-agentic-workflow
./scripts/install-global.sh
```

Then restart Claude Code.
