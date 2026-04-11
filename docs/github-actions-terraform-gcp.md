# GitHub Actions CI/CD Setup for Terraform on GCP

## Overview

This guide explains how to set up GitHub Actions for Terraform CI/CD on Google Cloud using:

- **Workload Identity Federation (WIF)**
- **GitHub repository variables**
- **Terraform plan on pull request**
- **Terraform apply on push to `main` after merge**

This approach avoids service account keys and uses short-lived credentials.

---

## Expected Behavior

The workflow is designed to do this:

- **Pull request**
  - run `terraform fmt`
  - run `terraform validate`
  - run `terraform plan`
  - post or update a PR comment with a plan summary

- **Push to `main`**
  - run `terraform apply`

This means reviewers can see the infrastructure diff before merge, while deployment happens only after code lands on `main`.

---

## Repository Structure Assumed

This guide assumes your repo looks like this:

```text
sorrow-infra/
├── .github/
│   └── workflows/
│       └── terraform.yml
├── envs/
│   └── bld/
│       ├── backend.hcl
│       └── terraform.tfvars
├── live/
│   └── bld/
│       ├── main.tf
│       ├── provider.tf
│       ├── variables.tf
│       └── versions.tf
└── modules/
```

The Terraform root module for this environment is:

```text
live/bld
```

---

## Prerequisites

You should already have:

- a GCP project, for example `build-000`
- a Terraform service account, for example `terraform-dev@build-000.iam.gserviceaccount.com`
- a remote Terraform backend already working
- a GitHub repository for your Terraform code

---

## 1. Create a Workload Identity Pool

```bash
PROJECT_ID="build-000"
POOL_ID="github-pool"

gcloud iam workload-identity-pools create "${POOL_ID}"   --project="${PROJECT_ID}"   --location="global"   --display-name="GitHub Actions Pool"
```

---

## 2. Create a GitHub OIDC Provider

```bash
PROJECT_ID="build-000"
POOL_ID="github-pool"
PROVIDER_ID="github-provider"
REPO="aj99hall/sorrow-infra"

gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_ID}"   --project="${PROJECT_ID}"   --location="global"   --workload-identity-pool="${POOL_ID}"   --display-name="GitHub Provider"   --issuer-uri="https://token.actions.githubusercontent.com"   --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.aud=assertion.aud,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref"   --attribute-condition="assertion.repository=='${REPO}'"
```

---

## 3. Get the Project Number

The workload identity provider string requires the **project number**, not just the project ID.

Get it with:

```bash
gcloud projects describe build-000 --format="value(projectNumber)"
```

Example output:

```text
1081177416975
```

---

## 4. Allow GitHub to Impersonate the Terraform Service Account

```bash
PROJECT_ID="build-000"
PROJECT_NUMBER="1081177416975"
POOL_ID="github-pool"
REPO="aj99hall/sorrow-infra"
SA="terraform-dev@build-000.iam.gserviceaccount.com"

gcloud iam service-accounts add-iam-policy-binding "${SA}"   --project="${PROJECT_ID}"   --role="roles/iam.workloadIdentityUser"   --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${REPO}"
```

If your organization enforces `iam.allowedPolicyMemberDomains`, this step may fail until an org policy admin allows the workload identity principal.

---

## 5. Enable Required APIs

At minimum, make sure these APIs are enabled in the correct project:

```bash
gcloud services enable iamcredentials.googleapis.com --project=build-000
gcloud services enable cloudresourcemanager.googleapis.com --project=build-000
```

If you use additional resource types, enable the related APIs too.

---

## 6. Grant Permissions to the Terraform Service Account

The service account used by GitHub Actions needs permission to:

- read and write the Terraform state backend
- read project metadata
- create, update, or delete the resources managed by Terraform

Example:

```bash
gcloud projects add-iam-policy-binding build-000   --member="serviceAccount:terraform-dev@build-000.iam.gserviceaccount.com"   --role="roles/storage.admin"
```

Add additional roles based on the actual infrastructure you manage.

---

## 7. Use a Simple Terraform Provider in CI

When GitHub Actions already authenticates through WIF and the target service account, the Terraform provider should stay simple.

Use:

```hcl
provider "google" {
  project = var.project_id
  region  = var.region
}
```

Do **not** add:

```hcl
impersonate_service_account = ...
```

for this GitHub Actions path, because that can cause an unnecessary second impersonation hop and lead to `iam.serviceAccounts.getAccessToken` errors.

---

## 8. Add GitHub Repository Variables

In GitHub, go to:

```text
Settings → Secrets and variables → Actions → Variables
```

Create these repository variables:

- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `GCP_SERVICE_ACCOUNT`
- `GCP_PROJECT_ID`
- `GCP_REGION`

For this environment, the values would be:

```text
GCP_WORKLOAD_IDENTITY_PROVIDER=projects/1081177416975/locations/global/workloadIdentityPools/github-pool/providers/github-provider
GCP_SERVICE_ACCOUNT=terraform-dev@build-000.iam.gserviceaccount.com
GCP_PROJECT_ID=build-000
GCP_REGION=europe-west2
```

These are not secrets, so repository variables are appropriate.

---

## 9. Optional: Protect Apply with a GitHub Environment

To require approval before apply, create a GitHub environment named:

```text
bld
```

Then configure:

- required reviewers
- optional prevent self-review
- deployment branches restricted to `main`

In the workflow, the apply job uses:

```yaml
environment: bld
```

So those rules will gate deployment.

---

## 10. Use This Workflow File

Create:

```text
.github/workflows/terraform.yml
```

With this content:

```yaml
name: Terraform GCP

on:
  pull_request:
    paths:
      - "live/**"
      - "modules/**"
      - "envs/**"
      - ".github/workflows/terraform.yml"

  push:
    branches:
      - "main"
    paths:
      - "live/**"
      - "modules/**"
      - "envs/**"
      - ".github/workflows/terraform.yml"

permissions:
  id-token: write
  contents: read
  pull-requests: write

concurrency:
  group: terraform-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

env:
  TF_IN_AUTOMATION: "true"
  TF_ROOT: live/bld

jobs:
  plan:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.14.3
          terraform_wrapper: false

      - name: Terraform Init
        run: terraform -chdir=${TF_ROOT} init -backend-config=../../envs/bld/backend.hcl

      - name: Terraform Fmt
        run: terraform -chdir=${TF_ROOT} fmt -check -recursive

      - name: Terraform Validate
        run: terraform -chdir=${TF_ROOT} validate

      - name: Terraform Plan
        run: |
          terraform -chdir=${TF_ROOT} plan             -input=false             -out=tfplan             -var="project_id=${{ vars.GCP_PROJECT_ID }}"             -var="region=${{ vars.GCP_REGION }}"

          terraform -chdir=${TF_ROOT} show -json tfplan > ${TF_ROOT}/plan.json

      - name: Generate plan summary
        run: |
          ADDS=$(jq '[.resource_changes[] | select(.change.actions | index("create"))] | length' ${TF_ROOT}/plan.json)
          UPDATES=$(jq '[.resource_changes[] | select(.change.actions | index("update"))] | length' ${TF_ROOT}/plan.json)
          DELETES=$(jq '[.resource_changes[] | select(.change.actions | index("delete"))] | length' ${TF_ROOT}/plan.json)
          REPLACES=$(jq '[.resource_changes[] | select((.change.actions | index("delete")) and (.change.actions | index("create")))] | length' ${TF_ROOT}/plan.json)

          VM_RECREATION=$(jq '
            [.resource_changes[]
              | select(
                  (.type == "google_compute_instance")
                  and (.change.actions | index("delete"))
                )
            ] | length
          ' ${TF_ROOT}/plan.json)

          {
            echo "### Terraform Plan Summary"
            echo
            echo "| Action | Count |"
            echo "|-------:|------:|"
            echo "| ➕ Create | $ADDS |"
            echo "| ✏️ Update | $UPDATES |"
            echo "| ❌ Delete | $DELETES |"
            echo "| 🔁 Replace | $REPLACES |"
            echo

            if [ "$VM_RECREATION" -gt 0 ]; then
              echo "🚨 **DANGER ZONE** 🚨"
              echo
              echo "**Compute Engine VM recreation detected.**"
              echo
              echo "- This will restart Airflow services"
              echo "- SQLite metadata DB is at risk during restarts"
              echo "- Scheduler downtime is expected"
              echo
            fi

            echo "\`\`\`"
            echo "${TF_ROOT}"
            echo "\`\`\`"
          } > summary.md

      - name: Upload plan summary
        uses: actions/upload-artifact@v4
        with:
          name: tf-plan-summary
          path: summary.md

  comment-plan:
    if: github.event_name == 'pull_request'
    needs: plan
    runs-on: ubuntu-latest

    permissions:
      contents: read
      pull-requests: write
      issues: write

    steps:
      - name: Download plan summary
        uses: actions/download-artifact@v4
        with:
          name: tf-plan-summary
          path: .

      - name: Comment or update Terraform plan on PR
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const body = fs.readFileSync('summary.md', 'utf8');

            const { data: comments } = await github.rest.issues.listComments({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
            });

            const marker = "### Terraform Plan Summary";
            const existing = comments.find(c =>
              c.user.type === "Bot" && c.body.includes(marker)
            );

            if (existing) {
              await github.rest.issues.updateComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                comment_id: existing.id,
                body
              });
            } else {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: context.issue.number,
                body
              });
            }

  apply:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: bld

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.14.3
          terraform_wrapper: false

      - name: Terraform Init
        run: terraform -chdir=${TF_ROOT} init -backend-config=../../envs/bld/backend.hcl

      - name: Terraform Apply
        run: |
          terraform -chdir=${TF_ROOT} apply             -input=false             -auto-approve             -var="project_id=${{ vars.GCP_PROJECT_ID }}"             -var="region=${{ vars.GCP_REGION }}"
```

---

## 11. Test the Workflow

A safe first test is a throwaway GCS bucket.

Example resource:

```hcl
resource "google_storage_bucket" "gha_test" {
  name                        = "sorrow-build-000-gha-test-20260411"
  location                    = "EU"
  uniform_bucket_level_access = true

  labels = {
    managed_by = "terraform"
    env        = "bld"
    purpose    = "gha-test"
  }
}
```

Then:

1. create a feature branch
2. commit and push the resource
3. open a PR
4. confirm the plan workflow runs
5. merge to `main`
6. confirm the apply workflow runs
7. verify the bucket exists in GCP

---

## Common Problems

### `iam.serviceAccounts.getAccessToken` denied

Cause:
- Terraform provider is trying to impersonate a service account again

Fix:
- remove `impersonate_service_account` from the provider

---

### `IAM Service Account Credentials API has not been used`

Cause:
- API is disabled in the relevant project
- or was only just enabled and has not propagated yet

Fix:
- enable `iamcredentials.googleapis.com`
- wait a few minutes
- retry

---

### `allowedPolicyMemberDomains` blocks WIF binding

Cause:
- organization policy is preventing the `principalSet://...` member from being added

Fix:
- ask an org policy admin to allow the workload identity principal

---

### Plan JSON file not found

Cause:
- `terraform show -json tfplan > plan.json` writes to the repo root, not `live/bld`

Fix:
- use:

```bash
terraform -chdir=${TF_ROOT} show -json tfplan > ${TF_ROOT}/plan.json
```

---

## Summary

This setup gives you:

- plan on pull request
- apply on merge to `main`
- no service account JSON keys
- GitHub repository variables instead of hard-coded config
- optional approval gates via GitHub environments

That is a solid default CI/CD setup for Terraform on GCP.
