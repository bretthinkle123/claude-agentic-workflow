# <Directory name>

> Per-directory README template. Fill in; delete sections that don't apply.
> Update only affected sections on later changes — diff, don't rewrite.

## Purpose

One or two sentences: what this directory is responsible for and why it exists.

## Modules

| File / module | Responsibility |
|---|---|
| `<file>` | <one line> |

## Relationships

How the modules here relate to each other and to the rest of the system. Note
the public surface (what other code imports) versus internals hidden behind it.
If this directory is a facade (auth, logging, config), say so and name the
public entry points.

## Notes (optional)

Non-obvious constraints, env vars consumed, or gotchas a maintainer needs.
