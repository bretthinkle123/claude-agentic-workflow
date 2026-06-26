#!/bin/bash
# Confirms the deployed instance is healthy. Failure surfaces for manual
# rollback decision — never auto-loops into debugging against production.
#
# NOTE: this is a CI hook — run it in CI after the PR is merged and CI deploys,
# NOT as a pipeline Stop hook (the deployment agent stops at the PR; there is no
# live instance to probe yet). See docs/pipeline-deployment-targets.md for wiring it
# into a GitHub Actions workflow.

DEPLOY_URL="${DEPLOY_HEALTH_URL:?Set DEPLOY_HEALTH_URL}"
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$DEPLOY_URL/health")

if [ "$HEALTH" != "200" ]; then
  echo "Post-deploy check failed: $DEPLOY_URL returned $HEALTH. Manual rollback review needed." >&2
  exit 2
fi

exit 0
