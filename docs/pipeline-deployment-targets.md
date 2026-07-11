# Pipeline deployment targets (companion to `system_architecture.md`)

Documentation-only. **Nothing here is loaded at pipeline runtime** — this covers everything that happens *after* the deployment agent opens a PR on GitHub. The pipeline's job ends at the PR; production delivery is handled by CI/CD after the PR is merged.

**When to use this file:** when you are ready to wire up a production delivery path for a specific project. Copy the relevant pattern into a GitHub Actions workflow or CI config.

Contents:
- [Where the pipeline ends](#where-the-pipeline-ends)
- [GitHub Actions — general CD pattern](#github-actions-cd)
- [AWS ECS (container app)](#aws-ecs)
- [AWS Lambda (serverless)](#aws-lambda)
- [Database migrations (Alembic / Python)](#db-migrations)
- [Terraform infrastructure apply](#terraform-apply)
- [Post-deploy health check (CI hook)](#post-deploy-check)
- [Apple App Store (iOS — Fastlane)](#apple-app-store)
- [Google Play Store (Android — Gradle)](#google-play)
- [Rollback procedure](#rollback)

---

<a id="where-the-pipeline-ends"></a>
## Where the pipeline ends

The deployment agent's last action is `gh pr create`. After that:

```
Pipeline boundary
      │
      ▼
  PR opened on GitHub
      │
      ▼
  (you review + merge, or set up auto-merge rules)
      │
      ▼
  GitHub Actions triggers on merge → main
      │
      ├── run CI tests (optional redundancy)
      ├── DB migrations
      ├── terraform apply (if infra changed)
      ├── application deploy (ECS / Lambda / etc.)
      └── post-deploy health check
```

The `post-deploy-check.sh` script in the pipeline's hook templates section is a reference for what to put in the CI health-check step — same logic, runs in the GitHub Actions runner instead of locally.

---

<a id="github-actions-cd"></a>
## GitHub Actions — general CD pattern

Create `.github/workflows/deploy.yml` in your project:

```yaml
name: Deploy

on:
  push:
    branches: [main]

permissions:
  id-token: write   # needed for OIDC role assumption
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC — no long-lived keys)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Run DB migrations
        run: alembic upgrade head       # adjust to your migrate command

      - name: Terraform apply (if infra changed)
        run: |
          cd infra
          terraform init -input=false
          terraform apply -auto-approve -input=false
        # Wrap in a condition if infra changes are infrequent:
        # if: contains(github.event.head_commit.modified, 'infra/')

      - name: Deploy application
        run: |
          # See AWS ECS or Lambda sections below for the specific command.
          echo "Insert deploy command here"

      - name: Post-deploy health check
        run: |
          # See post-deploy-check section below.
          curl -sf --retry 5 --retry-delay 5 \
            ${{ secrets.HEALTH_URL }} > /dev/null
```

**Required GitHub secrets:** `AWS_ROLE_ARN`, `AWS_REGION`, `HEALTH_URL`, and any app-specific secrets (from AWS Secrets Manager/SSM — pull them in the workflow, don't store them as GitHub secrets directly if you can avoid it).

---

<a id="aws-ecs"></a>
## AWS ECS (container app)

Typical stack: ECR (image registry) + ECS Fargate (container runtime) + ALB (load balancer).

**Deploy step in the GitHub Actions workflow:**

```bash
# Build and push the Docker image to ECR
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${GITHUB_SHA}"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin \
    "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker build -t "$IMAGE_URI" .
docker push "$IMAGE_URI"

# Force a new deployment — ECS pulls the new image
aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --force-new-deployment \
  --region "$AWS_REGION"

# Wait for the new task set to stabilize (times out after ~10 min)
aws ecs wait services-stable \
  --cluster "$ECS_CLUSTER" \
  --services "$ECS_SERVICE" \
  --region "$AWS_REGION"
```

**Required env vars / secrets:** `AWS_ACCOUNT_ID`, `ECR_REPO`, `ECS_CLUSTER`, `ECS_SERVICE`.

---

<a id="aws-lambda"></a>
## AWS Lambda (serverless)

Two common patterns — pick one:

**Pattern A — AWS SAM:**
```bash
sam build
sam deploy --no-confirm-changeset --no-fail-on-empty-changeset
```

**Pattern B — Serverless Framework:**
```bash
npx serverless deploy --stage production
```

**Pattern C — raw `aws lambda update-function-code` (single function, no IaC):**
```bash
zip -r function.zip . -x "*.git*"
aws lambda update-function-code \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --zip-file fileb://function.zip \
  --region "$AWS_REGION"
aws lambda wait function-updated \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --region "$AWS_REGION"
```

---

<a id="db-migrations"></a>
## Database migrations (Alembic / Python)

Run migrations **before** starting the new application version — a half-migrated schema against old code is recoverable; old code against a forward-migrated schema may not be.

```bash
# In the GitHub Actions deploy job, before the ECS/Lambda deploy step:
pip install alembic psycopg2-binary   # or from requirements.txt
export DATABASE_URL="${{ secrets.DATABASE_URL }}"
alembic upgrade head
```

**On failure:** stop the workflow immediately (default behavior — any non-zero exit code halts a GitHub Actions step). Do not proceed to the application deploy. Roll the migration back manually with `alembic downgrade -1` (or to a named revision).

**JavaScript equivalent (Knex):**
```bash
npx knex migrate:latest --env production
```

---

<a id="terraform-apply"></a>
## Terraform infrastructure apply

The `infra-validate.sh` pipeline hook runs `terraform plan` and writes it to `.pipeline/infra-plan.txt` for your review at the planning checkpoint. `terraform apply` runs here in CI — after the PR is merged, not before.

```bash
# In the GitHub Actions deploy job:
cd infra
terraform init \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="dynamodb_table=${TF_LOCK_TABLE}" \
  -input=false

# Re-run plan to get a fresh plan against the current state
terraform plan -out=tfplan -input=false

# Apply the plan
terraform apply -auto-approve tfplan
```

**Credentials:** use the OIDC role assumption step at the top of the workflow — no long-lived AWS keys. The deploy role should be least-privilege (scoped to exactly the services in the stack).

**On failure:** Terraform writes a detailed error to stdout. Do not retry automatically — investigate drift manually before re-applying.

---

<a id="post-deploy-check"></a>
## Post-deploy health check (CI hook)

This is the CI equivalent of the pipeline's `post-deploy-check.sh` template. Add it as the last step in the deploy job:

```bash
#!/usr/bin/env bash
# Post-deploy health check — run in CI after the deploy step.
# Set HEALTH_URL to the production health endpoint.

HEALTH_URL="${HEALTH_URL}"   # e.g. https://api.yourdomain.com/health
MAX_RETRIES=5
RETRY_DELAY=10

for i in $(seq 1 "$MAX_RETRIES"); do
  if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
    echo "[post-deploy] PASS — $HEALTH_URL responded 200"
    exit 0
  fi
  echo "[post-deploy] Attempt $i/$MAX_RETRIES failed; retrying in ${RETRY_DELAY}s..."
  sleep "$RETRY_DELAY"
done

echo "[post-deploy] FAIL — $HEALTH_URL did not respond after $MAX_RETRIES attempts" >&2
exit 2
# Non-zero exit code fails the GitHub Actions job and blocks future deploys until fixed.
# Rollback manually — see the rollback section below.
```

---

<a id="apple-app-store"></a>
## Apple App Store (iOS — Fastlane)

Prerequisites: Xcode installed on a macOS CI runner, an Apple Developer account, an App Store Connect API key (stored as a GitHub secret), and [Fastlane](https://fastlane.tools/) installed.

**`Fastfile` lane (add to `fastlane/Fastfile` in your iOS project):**
```ruby
lane :release do
  # Increment build number using the git commit count
  increment_build_number(
    build_number: sh("git rev-list --count HEAD").strip
  )

  # Code sign using App Store Connect API key (no passwords stored)
  api_key = app_store_connect_api_key(
    key_id: ENV["ASC_KEY_ID"],
    issuer_id: ENV["ASC_ISSUER_ID"],
    key_content: ENV["ASC_KEY_CONTENT"],  # base64-encoded .p8 contents
  )

  # Build archive
  gym(
    scheme: ENV.fetch("XCODE_SCHEME", "MyApp"),
    export_method: "app-store",
    clean: true,
  )

  # Upload to App Store Connect (TestFlight + review submission)
  upload_to_app_store(
    api_key: api_key,
    submit_for_review: false,   # set true to auto-submit; false = TestFlight only
    skip_metadata: true,
    skip_screenshots: true,
  )
end
```

**GitHub Actions step:**
```yaml
- name: Deploy to App Store (TestFlight)
  run: bundle exec fastlane release
  env:
    ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
    ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
    ASC_KEY_CONTENT: ${{ secrets.ASC_KEY_CONTENT }}
    XCODE_SCHEME: MyApp
```

**App Store review requirements (checklist before setting `submit_for_review: true`):**
- Privacy manifest (`PrivacyInfo.xcprivacy`) present and accurate
- App Store Connect metadata complete (description, keywords, screenshots per device size)
- Age rating configured
- Export compliance answered
- Any third-party SDKs declared in the privacy manifest

---

<a id="google-play"></a>
## Google Play Store (Android — Gradle)

Prerequisites: a Google Play Developer account, a service account JSON key with "Release manager" access to your app (stored as a GitHub secret), and the [Gradle Play Publisher plugin](https://github.com/Triple-T/gradle-play-publisher).

**`build.gradle.kts` plugin setup:**
```kotlin
plugins {
    id("com.github.triplet.play") version "3.9.1"
}

play {
    serviceAccountCredentials.set(file(System.getenv("PLAY_SERVICE_ACCOUNT_JSON") ?: "play-credentials.json"))
    track.set("internal")   // "internal" → "alpha" → "beta" → "production"
    defaultToAppBundles.set(true)
}
```

**GitHub Actions step:**
```yaml
- name: Deploy to Google Play (internal track)
  run: ./gradlew bundleRelease publishReleaseBundle
  env:
    PLAY_SERVICE_ACCOUNT_JSON: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
    KEYSTORE_FILE: ${{ secrets.KEYSTORE_FILE }}          # base64-encoded .jks
    KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
    KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
    STORE_PASSWORD: ${{ secrets.STORE_PASSWORD }}
```

Promote from `internal` → `production` manually in the Play Console, or add a second workflow step that calls `./gradlew promoteReleaseArtifact --from-track internal --promote-track production` after QA sign-off.

---

<a id="rollback"></a>
## Rollback procedure

**Application rollback (ECS):**
```bash
# Find the previous task definition revision
aws ecs describe-services \
  --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
  --query "services[0].taskDefinition"

# Re-deploy the previous revision
aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --task-definition "${TASK_FAMILY}:${PREVIOUS_REVISION}" \
  --region "$AWS_REGION"
```

**Application rollback (Lambda):**
```bash
# Lambda keeps the last N versions — roll back by aliasing to the previous version
aws lambda update-alias \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --name production \
  --function-version "$PREVIOUS_VERSION"
```

**Database rollback (Alembic):**
```bash
# Roll back one migration
alembic downgrade -1

# Roll back to a specific revision
alembic downgrade <revision_id>
```

> **Do not auto-rollback production.** A post-deploy failure may mean the new code is wrong, or it may mean the health check is wrong, or it may be a transient network issue. Investigate before rolling back — a rollback against a forward-only migration can cause data loss.

**Git revert (last resort — bad commit already merged):**
```bash
git revert HEAD --no-edit
git push origin main
# This triggers a new CI deploy of the reverted code, which is safe.
# Do NOT force-push to main.
```
