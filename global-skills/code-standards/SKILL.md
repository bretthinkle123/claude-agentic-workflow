---
name: code-standards
description: Naming, function size, comment/docstring rules, the five SOLID principles with smell tests, and how to structure facade modules — the implementation agent's one coding-standards reference.
---

# Code standards

Apply to every file you touch. Default backend is **Python**, default frontend
**JavaScript**. For a concrete SOLID before/after, read `examples.md` (sibling).

## Clean code

- **Naming** — intent-revealing names for every variable, parameter, and
  function. No single-letter names except loop counters. No abbreviations unless
  universally understood in the domain (`id`, `url`, `http` are fine).
- **Function size / single level of abstraction** — a function does one thing at
  one level. If you're mixing high-level orchestration with low-level detail in
  the same body, extract the detail.
- **Comments** — comment the **why**, not the **what**. Explain non-obvious
  constraints, workarounds, and invariants. Delete comments that restate the code.
- **Docstrings** — non-trivial functions and classes get a one-line docstring
  (Python/JSDoc/Go doc comment). Skip trivial getters and obvious helpers.

## SOLID (apply on every class / module / function boundary)

| Principle | Smell test | Fix |
|---|---|---|
| **Single Responsibility** | The unit has more than one reason to change | Split by axis of change |
| **Open/Closed** | You edit existing code to add a variant | Extend via a new type/strategy, not modification |
| **Liskov Substitution** | A subtype throws/no-ops on a base method, or narrows behavior | Don't subtype; compose or re-model |
| **Interface Segregation** | Implementers stub methods they don't need | Split the fat interface into focused ones |
| **Dependency Inversion** | A module hard-news/imports a concrete dependency | Depend on an abstraction; inject the dependency |

## Facade and centralized modules

Route cross-cutting concerns — **auth checks, logging, error handling, config
access** — through centralized facade modules, never scattered inline calls.

- A facade has a **small, stable public surface**; implementation details hide
  behind it.
- New features **plug into existing facades**; they do not bypass them. If a
  needed facade doesn't exist, **create it as part of this change** and route new
  code through it.
- Worked facade examples live in the on-demand `auth-patterns` (the `auth/`
  guard facade) and `logging-conventions` (the single configured logger) skills —
  invoke them when the change touches those layers.
