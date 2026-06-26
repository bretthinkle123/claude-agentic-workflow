---
name: containerization-conventions
description: When containerizing (Docker) an application is good practice vs. running it as a direct process or serverless function — the decision rubric, the Kubernetes-vs-managed-runtime call, Dockerfile/image conventions, and threat-model touchpoints. Invoke from planning whenever the runtime/packaging of the app is in question.
---

# Containerization conventions (planning decision guide)

Invoke this when a plan must decide **how the app is packaged and run**. Record the
call and its rationale under `## Stack notes` like any other default-stack decision —
never silently containerize.

## When to containerize (the decision rubric)

Default to the **simplest runtime that fits** — a direct process. Reach for Docker
only when one or more of these hold:

- The app has **non-trivial system/native dependencies** that are painful to
  reproduce across environments.
- Strict **dev/CI/prod parity** matters (the "works on my machine" class of bug).
- The target platform is **container-native** (ECS/Fargate, EKS, Cloud Run, any k8s).
- You need to **horizontally scale** long-running workers / background processors.
- **Several services** must be composed together locally.

Prefer **serverless (Lambda)** instead when the workload is event-driven, spiky, and
short-lived. Prefer a **direct process** for a simple single-runtime app where a
container adds operational overhead without a parity or platform win.

## Kubernetes vs. a managed container runtime

Do **not** reach for Kubernetes by default. It earns its operational complexity only
above a threshold — many services, sophisticated rollout/scaling/networking needs, and
ideally an existing platform team. For most projects a **managed runtime** (ECS/Fargate,
Cloud Run) delivers containers without the cluster burden. Record which and why; if k8s
is genuinely warranted, say what specifically requires it.

## Image / Dockerfile conventions (only once containerizing is chosen)

- **Multi-stage builds** — build-time deps never reach the runtime image.
- **Pinned, minimal base images** (`python:3.x-slim`, distroless where practical).
- Run as a **non-root** user.
- **No secrets baked into layers or build args** — inject at runtime.
- A **`.dockerignore`** to keep the build context (and image) small.
- **Deterministic dependency installs** from lockfiles.

## Threat-model touchpoints (feed into the STRIDE step)

- Base-image and OS-package **CVEs**.
- Running as **root**.
- **Secrets** embedded in image layers or build args.
- Over-broad **registry/pull credentials**.

## Scope note (deferred wiring)

This skill is **planning-only** for now: the decision and its threat-model
implications. Authoring the Dockerfile / Kubernetes manifests in implementation and
**image scanning** (e.g. Trivy) in security are a known, deferred gap — there is no
designated home or scanner for those artifacts yet. Until then, planning surfaces the
decision at the human checkpoint and CI handles delivery (see
`pipeline-deployment-targets.md`).
