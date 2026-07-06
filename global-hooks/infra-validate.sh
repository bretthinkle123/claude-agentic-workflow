#!/bin/bash
# Deterministic infra gate: format, validate, and produce a reviewable plan.
# No-ops when the change has no infra/ directory.
set -e
# Pipeline-project guard: installed globally; no-op outside a bootstrapped pipeline
# project (no .pipeline/state.json) before touching any infra/ in an unrelated repo.
[ -f .pipeline/state.json ] || exit 0
[ -d infra ] || exit 0

cd infra
terraform fmt -check
terraform init -backend=false
terraform validate
# Write the plan for the human checkpoint; this exits non-zero only on error, not on diff.
mkdir -p ../.pipeline
terraform plan -no-color > ../.pipeline/infra-plan.txt
echo "Infra validated; plan written to .pipeline/infra-plan.txt for review." >&2
exit 0
