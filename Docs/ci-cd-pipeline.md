# CI/CD Pipeline Documentation

> **Audience**: DevOps engineers, platform engineers, and developers who need to understand, modify, or troubleshoot the CI/CD pipeline.

---

## Table of Contents

- [GitOps Philosophy](#-gitops-philosophy)
- [Pipeline Overview](#-pipeline-overview)
- [Workflow Files](#-workflow-files)
- [The Plan-Apply Split Pattern](#-the-plan-apply-split-pattern)
- [Sequential Execution Order](#-sequential-execution-order)
- [Reusable Workflows](#-reusable-workflows)
- [Headless Init Fix Explained](#-headless-init-fix-explained)
- [State Key Strategy](#-state-key-strategy)
- [Plan Binary Artifacts](#-plan-binary-artifacts)
- [Adding a New Spoke to the Pipeline](#-adding-a-new-spoke-to-the-pipeline)
- [Adding a New Environment](#-adding-a-new-environment)
- [Troubleshooting CI/CD](#-troubleshooting-cicd)
- [Security in the Pipeline](#-security-in-the-pipeline)

---

## 🤖 GitOps Philosophy

This pipeline follows **GitOps** principles:

1. **Git is the single source of truth** — All infrastructure definitions live in this repository
2. **Pull Requests drive change** — Every modification goes through a PR with automated planning
3. **Review before apply** — Team members review `terraform plan` output in the PR before merging
4. **Reconcilation loop** — The pipeline continuously ensures the cloud matches what's in Git
5. **No manual apply** — Never run `terraform apply` on a local machine for production changes

```
         ┌─────────────────────────────────┐
         │       Developer pushes code      │
         │       to feature branch          │
         └──────────────┬──────────────────┘
                        │
                        ▼
         ┌─────────────────────────────────┐
         │       Open Pull Request          │
         │    (feature → main)              │
         └──────────────┬──────────────────┘
                        │
                        ▼
         ┌─────────────────────────────────┐
         │   CI: terraform fmt + validate   │
         │   + terraform plan               │
         └──────────────┬──────────────────┘
                        │
                        ▼
         ┌─────────────────────────────────┐
         │    Team reviews plan output      │
         │    in PR comments                │
         └──────────────┬──────────────────┘
                        │
                        ▼
         ┌─────────────────────────────────┐
         │    Merge to main                 │
         └──────────────┬──────────────────┘
                        │
                        ▼
         ┌─────────────────────────────────┐
         │   CD: terraform apply with       │
         │   exact PR-compiled plan         │
         └─────────────────────────────────┘
```

---

## 📐 Pipeline Overview

### Trigger Events

The pipeline is triggered by two events:

| Event | Branch | Path Filter | Purpose |
|-------|--------|-------------|---------|
| `pull_request` | `main` | `Workload/Spokes/fintrack/**` or `Deployment/Spokes/fintrack/**` | Run `terraform plan` for review |
| `push` | `main` | `Workload/Spokes/fintrack/**` | Run `terraform apply` for deployment |

> **Path filtering**: Changes outside the watched paths (e.g., changes to `Modules/` core structure or `Docs/`) **do not** trigger the pipeline. This is by design — module changes are tested through spoke usage.

### Pipeline at a Glance

```
PR EVENT                          MERGE EVENT
─────────                         ───────────

┌─ plan-network ─┐               ┌─ apply-network ─┐
│ ✓ fmt -check   │               │ ✓ init          │
│ ✓ init         │               │ ✓ download plan │
│ ✓ validate     │               │ ✓ apply         │
│ ✓ plan -out    │               └──────────────────┘
│ ✓ upload       │                        │
└────────────────┘                        ▼
        │                      ┌─ apply-data ────┐
        ▼                      │ ✓ init          │
┌─ plan-data ───┐              │ ✓ download plan │
│ ✓ fmt -check  │              │ ✓ apply         │
│ ✓ init        │              └──────────────────┘
│ ✓ validate    │                       │
│ ✓ plan -out   │                       ▼
│ ✓ upload      │              ┌─ apply-identity ┐
└────────────────┘              │ ✓ init          │
        │                      │ ✓ download plan │
        ▼                      │ ✓ apply         │
┌─ plan-identity ┐              └──────────────────┘
│ ✓ fmt -check   │
│ ✓ init         │
│ ✓ validate     │
│ ✓ plan -out    │
│ ✓ upload       │
└────────────────┘
```

---

## 📁 Workflow Files

### 1. `fintrack-pipeline.yml` — The Orchestrator

This is the **entry point** workflow. It defines:
- **When** to run (PR to `main`, Push to `main`)
- **Which** files trigger it (path filters)
- **The order** of jobs (via `needs:` dependencies)
- **Which** reusable workflow to call for each job

```yaml
# Key structure
jobs:
  plan-network:     # PR only: Plan the network layer
    if: github.event_name == 'pull_request'
    uses: ./.github/workflows/terraform-plan.yml
    with:
      working_directory: 'Workload/Spokes/fintrack/network'
      tfvars_file: '../../../../Deployment/Spokes/fintrack/dev.tfvars'
      state_key: 'spokes/fintrack/network.tfstate'
      artifact_name: 'fintrack-network-tfplan'
    secrets: inherit

  plan-data:        # PR only: Plan data layer AFTER network
    if: github.event_name == 'pull_request'
    needs: plan-network
    # ... same pattern

  plan-identity:    # PR only: Plan identity layer AFTER data
    if: github.event_name == 'pull_request'
    needs: plan-data
    # ... same pattern

  apply-network:    # Merge only: Apply network
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    # ... calls terraform-apply.yml

  apply-data:       # Merge only: Apply data AFTER network applied
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    needs: apply-network
    # ... calls terraform-apply.yml

  apply-identity:   # Merge only: Apply identity AFTER data applied
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    needs: apply-data
    # ... calls terraform-apply.yml
```

### 2. `terraform-plan.yml` — Reusable CI Workflow

Called by the orchestrator for **each plan job**. Handles:

1. **Checkout** — Pull the code from the PR branch
2. **Setup Terraform** — Install Terraform 1.5.7
3. **Format Check** — `terraform fmt -check` ensures consistent code style
4. **Init** — Initialize with backend config pointing to DigitalOcean Spaces
5. **Validate** — `terraform validate` checks syntax and internal consistency
6. **Plan** — `terraform plan -out=tfplan` creates an executable plan binary
7. **Upload Artifact** — Save the plan binary for the apply stage

```yaml
# Key parameters (workflow_call inputs):
inputs:
  working_directory:  # e.g., "Workload/Spokes/fintrack/network"
  tfvars_file:        # Path to .tfvars from working directory
  state_key:          # State file path in Spaces, e.g., "spokes/fintrack/network.tfstate"
  artifact_name:      # Unique name for plan artifact, e.g., "fintrack-network-tfplan"
```

### 3. `terraform-apply.yml` — Reusable CD Workflow

Called by the orchestrator for **each apply job**. Handles:

1. **Checkout** — Pull `main` branch after merge
2. **Setup Terraform** — Same Terraform version as plan
3. **Init** — Same backend configuration as plan (ensures consistency)
4. **Download Artifact** — Fetch the plan binary produced during the PR phase
5. **Apply** — `terraform apply tfplan` executes the pre-compiled plan

```yaml
# Key difference from plan workflow:
# No fmt -check, no validate, no plan
# Just: init → download → apply
```

---

## 🔄 The Plan-Apply Split Pattern

### Why Split Plan and Apply?

| Reason | Explanation |
|--------|-------------|
| **Safety** | Review plan output before execution |
| **Auditability** | Every change has a recorded plan in the PR |
| **Consistency** | The exact same plan binary is used in apply — no drift |
| **Least Privilege** | CI only needs read access; CD needs write access |
| **Rollback** | Can reject a PR without ever touching infrastructure |

### How It Works

**Stage 1 — Pull Request (CI)**:
```
terraform plan -out=tfplan
    ↓
Upload tfplan as workflow artifact
    ↓
Review plan in PR comments
```

**Stage 2 — Merge to main (CD)**:
```
Download tfplan artifact (same binary from PR)
    ↓
terraform apply tfplan
```

> 🔑 **Critical**: The plan binary (`tfplan`) is a **snapshot** of exactly what will be created. It includes the Terraform configuration, state references, and execution graph. Applying this same binary on merge guarantees that what was reviewed is what gets applied — even if someone pushed a change to `main` between the PR and the merge.

### What's in a Plan Binary?

A `tfplan` file contains:
- The complete Terraform configuration at the time of planning
- The current state file contents
- The planned execution graph (what creates, modifies, or destroys)
- All variable values that were passed at plan time

This is why it's critical to **keep the artifact as a binary** (not human-readable text) — it's a self-contained execution package.

---

## 📋 Sequential Execution Order

### Why Sequential?

The layers have **data dependencies** that form a chain:

```text
Layer:           Needs Output:          From:
──────           ─────────────          ────
Spoke Network    hub_vpc_id             Core Network
Spoke Data       spoke_vpc_id           Spoke Network
Spoke Identity   droplet_urns           Spoke Network
                 database_urn           Spoke Data
```

These are enforced via the `needs:` keyword in GitHub Actions:

```yaml
plan-network:
  # No needs — first in sequence

plan-data:
  needs: plan-network      ← Wait for network plan to complete

plan-identity:
  needs: plan-data          ← Wait for data plan to complete
```

### What If Parallel Execution Were Allowed?

If all three layers planned simultaneously:
- **Spoke Data** would fail immediately (can't find spoke VPC state)
- **Spoke Identity** would fail immediately (can't find droplet or DB state)
- GitHub Actions would waste 3-10 minutes on failed jobs

### Execution Time

Typical timing per job (dev environment, small configuration):

| Job | Plan Time | Apply Time |
|-----|-----------|------------|
| Network (1 droplet + firewall) | ~30s | ~90s |
| Data (1 MongoDB node) | ~15s | ~120s |
| Identity (project binding) | ~10s | ~10s |
| **Total sequential** | **~55s** | **~220s** |

> Plan jobs run sequentially but each one is fast. The total block is about 1 minute of planning per PR.

---

## ♻️ Reusable Workflows

### Why Reusable Workflows?

Without reusable workflows, the pipeline file would repeat the same 20-line setup for each of the 6 jobs. Reusable workflows make the pipeline:

- **DRY** — Define the plan/apply logic once, call it 3 times each
- **Consistent** — Every layer gets the same init, validation, and apply process
- **Maintainable** — Update Terraform version or init flags in one place

### How `workflow_call` Works

```yaml
# terraform-plan.yml defines:
name: "Reusable Terraform Plan"
on:
  workflow_call:
    inputs:          # Parameters the caller must provide
      working_directory:
        required: true
        type: string
      tfvars_file:
        required: true
        type: string
      state_key:
        required: true
        type: string
      artifact_name:
        required: true
        type: string

# Called from pipeline:
plan-network:
  uses: ./.github/workflows/terraform-plan.yml
  with:
    working_directory: 'Workload/Spokes/fintrack/network'
    tfvars_file: '../../../../Deployment/Spokes/fintrack/dev.tfvars'
    state_key: 'spokes/fintrack/network.tfstate'
    artifact_name: 'fintrack-network-tfplan'
  secrets: inherit
```

### Secrets Inheritance

`secrets: inherit` passes **all** repository secrets from the caller workflow to the reusable workflow. This avoids needing to redeclare each secret in the `workflow_call` inputs.

---

## 🧠 Headless Init Fix Explained

### The Problem

Terraform's S3 backend supports **partial configuration**:

```hcl
# backend.tf
terraform {
  backend "s3" {}    # Empty — config provided at init time
}
```

This is useful for keeping secret values (access keys, bucket names) out of the codebase. However, in **headless CI environments**, `terraform init` with partial S3 config can **hang indefinitely** waiting for interactive input:

```
$ terraform init
Initializing the backend...

region
  AWS region of the S3 Bucket and DynamoDB Table (if used).

  Enter a value: _
```

This happens because:
1. DigitalOcean Spaces provides S3-compatible storage via an **endpoint URL** (`sgp1.digitaloceanspaces.com`)
2. The AWS S3 driver validates that a `region` is specified
3. Without `region`, Terraform prompts interactively
4. CI has no TTY, so it hangs until timeout

### The Fix

Inject `region=us-east-1` at init time:

```yaml
- name: Terraform Init
  run: |
    terraform init \
      -backend-config="bucket=${{ secrets.DO_SPACES_BUCKET }}" \
      -backend-config="endpoint=sgp1.digitaloceanspaces.com" \
      -backend-config="key=${{ inputs.state_key }}" \
      -backend-config="access_key=${{ secrets.DO_SPACES_ACCESS_KEY }}" \
      -backend-config="secret_key=${{ secrets.DO_SPACES_SECRET_KEY }}" \
      -backend-config="region=us-east-1"    # ← Bypasses the interactive prompt!
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.DO_SPACES_ACCESS_KEY }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.DO_SPACES_SECRET_KEY }}
```

### Why `us-east-1`?

DigitalOcean Spaces doesn't use AWS region names — it uses custom endpoints. The `region` value is only needed to satisfy the AWS SDK's internal validation. `us-east-1` is a safe dummy value that:
- Passes the SDK's format validation
- Doesn't affect how Terraform connects to Spaces (the `endpoint` URL determines the actual target)
- Works universally across all Spaces regions (sgp1, nyc3, ams3, etc.)

### Why Not Set It in `backend.tf`?

Setting `region` in `backend.tf` would hardcode a value that has no real meaning (Spaces doesn't use AWS regions). The CI injection approach keeps `backend.tf` clean and allows the dummy value to be documented inline where it matters most.

---

## 🔑 State Key Strategy

The `state_key` parameter determines **where** each layer's state file is stored in the Spaces bucket.

### State Key Convention

```text
{layer}/{module}.tfstate
```

| State Key | Layer | Why This Key |
|-----------|-------|-------------|
| `core/network/global.tfstate` | Hub Network | `core/` for hub, `global` because it's shared |
| `core/identity/global.tfstate` | Hub Identity | Same `core/` prefix |
| `spokes/fintrack/network.tfstate` | Spoke Network | `spokes/{app}/` organizes by application |
| `spokes/fintrack/data.tfstate` | Spoke Data | Same `spokes/{app}/` prefix |
| `spokes/fintrack/identity.tfstate` | Spoke Identity | Same `spokes/{app}/` prefix |

### Why This Convention?

1. **Namespacing** — `core/` vs `spokes/` prevents accidental collisions between hub and spoke states
2. **Discoverability** — All files for one application are grouped under `spokes/{app}/`
3. **Scalability** — Adding `spokes/payments/network.tfstate` is trivial and doesn't conflict
4. **Consistency** — The key mirrors the directory structure (`Workload/Spokes/fintrack/network`)

### How It Maps

```yaml
# In the pipeline:
state_key: 'spokes/fintrack/network.tfstate'

# Maps to Spaces bucket:
# fintrack-tfstate-bucket/spokes/fintrack/network.tfstate
```

---

## 📦 Plan Binary Artifacts

### What Gets Uploaded

Each plan job produces a `tfplan` file — an **immutable binary** that encodes the complete execution plan:

```
$ ls -la tfplan
-rw-r--r-- 1 root root 18432 ... tfplan   # ~18KB for small configs
```

### Artifact Naming Convention

```
{app}-{layer}-tfplan
```

| Artifact Name | Content |
|---------------|---------|
| `fintrack-network-tfplan` | Plan for `Workload/Spokes/fintrack/network` |
| `fintrack-data-tfplan` | Plan for `Workload/Spokes/fintrack/data` |
| `fintrack-identity-tfplan` | Plan for `Workload/Spokes/fintrack/identity` |

### Artifact Retention

```yaml
- name: Upload Plan Artifact
  uses: actions/upload-artifact@v4
  with:
    retention-days: 1    ← Plan artifacts expire after 1 day
```

**Why only 1 day retention?**
- PRs are typically reviewed and merged within 24 hours
- Plan binaries become invalid if someone pushes new commits to the branch
- Reduces storage costs on GitHub

> If a PR stays open longer than a day, push a new commit (even an empty one) to re-trigger the pipeline and get a fresh plan.

### How Apply Uses the Artifact

```yaml
- name: Download Plan Artifact
  uses: actions/download-artifact@v4
  with:
    name: ${{ inputs.artifact_name }}     # Matches the upload name
    path: ${{ inputs.working_directory }} # Places tfplan in the right directory

- name: Terraform Apply
  run: terraform apply -input=false tfplan  # Uses the exact same binary
  working-directory: ${{ inputs.working_directory }}
```

---

## ➕ Adding a New Spoke to the Pipeline

### Step-by-step Example: Adding "payments" App

**1. Create workload directories:**

```text
Workload/Spokes/payments/
├── network/
├── data/
└── identity/
```

Follow the same `.tf` file structure as `fintrack`.

**2. Create deployment configuration:**

```text
Deployment/Spokes/payments/dev.tfvars
```

**3. Add pipeline jobs (`fintrack-pipeline.yml`):**

```yaml
# PR phase
plan-payments-network:
  if: github.event_name == 'pull_request'
  uses: ./.github/workflows/terraform-plan.yml
  with:
    working_directory: 'Workload/Spokes/payments/network'
    tfvars_file: '../../../../Deployment/Spokes/payments/dev.tfvars'
    state_key: 'spokes/payments/network.tfstate'
    artifact_name: 'payments-network-tfplan'
  secrets: inherit

plan-payments-data:
  if: github.event_name == 'pull_request'
  needs: plan-payments-network
  uses: ./.github/workflows/terraform-plan.yml
  with:
    working_directory: 'Workload/Spokes/payments/data'
    tfvars_file: '../../../../Deployment/Spokes/payments/dev.tfvars'
    state_key: 'spokes/payments/data.tfstate'
    artifact_name: 'payments-data-tfplan'
  secrets: inherit

plan-payments-identity:
  if: github.event_name == 'pull_request'
  needs: plan-payments-data
  uses: ./.github/workflows/terraform-plan.yml
  with:
    working_directory: 'Workload/Spokes/payments/identity'
    tfvars_file: '../../../../Deployment/Spokes/payments/dev.tfvars'
    state_key: 'spokes/payments/identity.tfstate'
    artifact_name: 'payments-identity-tfplan'
  secrets: inherit

# Apply phase (mirror the pattern for apply-* jobs)
```

**4. Update path filters:**

```yaml
on:
  pull_request:
    paths:
      - 'Workload/Spokes/fintrack/**'
      - 'Deployment/Spokes/fintrack/**'
      - 'Workload/Spokes/payments/**'     # ← Add this
      - 'Deployment/Spokes/payments/**'   # ← Add this
```

> **Note**: The `plan-network` and `plan-data` etc. jobs are specific to `fintrack`. If multiple spokes should run in parallel **within** their own sequential chains, you'd need separate job names per spoke. They can execute concurrently because they operate on different state files.

---

## 🌍 Adding a New Environment

### Step-by-step: Adding "staging" for FinTrack

**1. Create deployment config:**

```text
Deployment/Spokes/fintrack/staging.tfvars
```

With production-like values:
```hcl
region             = "sgp1"
environment        = "staging"
app_name           = "fintrack"
state_bucket_name  = "fintrack-tfstate-bucket-staging"
droplet_size       = "s-2vcpu-2gb"
instance_count     = 2
db_size_slug       = "db-s-2vcpu-2gb"
db_node_count      = 2
initial_database   = "fintrack_staging_store"
```

**2. Add pipeline trigger paths:**

```yaml
on:
  pull_request:
    paths:
      - 'Deployment/Spokes/fintrack/staging.tfvars'  # ← Add
```

**3. (Optional) Create separate pipeline jobs for staging** — if you want staging deployments to run on push to a `staging` branch instead of `main`:

```yaml
on:
  push:
    branches: [staging]  # ← New trigger
    paths:
      - 'Workload/Spokes/fintrack/**'
      - 'Deployment/Spokes/fintrack/staging.tfvars'
```

---

## 🔧 Troubleshooting CI/CD

### Pipeline Doesn't Trigger

**Symptoms**: Push a commit, no workflow runs.

**Checklist**:
1. ✅ Are the changed files under the watched paths? (Check `paths:` in pipeline YAML)
2. ✅ Is the branch correct? (PR → `main`, push → `main`)
3. ✅ Is GitHub Actions enabled for the repository?
4. ✅ Are there any workflow syntax errors? (Check GitHub Actions tab)

### Plan Job Fails — "No works found"

**Symptom**: `terraform plan` runs but shows "No changes" when changes were expected.

**Cause**: The `tfvars_file` path is relative to the `working_directory`, not the repository root.
```yaml
# Correct:
tfvars_file: '../../../../Deployment/Spokes/fintrack/dev.tfvars'
# (Relative path from Workload/Spokes/fintrack/network → root → Deployment/...)
```

### Plan Job Fails — "Backend initialization required"

**Symptom**: Terraform can't find the backend configuration.

**Fix**: Check that all 5 `-backend-config` parameters are present:
- `bucket`
- `endpoint`
- `key`
- `access_key`
- `secret_key`
- `region` (the dummy fix)

And that `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` environment variables are set.

### Apply Job Fails — "Plan file was created by a different process"

**Symptom**: The downloaded plan binary can't be applied.

**Causes**:
1. Someone force-pushed to `main` between the PR plan and merge
2. The plan artifact expired (1-day retention)
3. The workflow was re-run from a different commit

**Fix**: Close and re-open the PR (or push a new commit) to generate a fresh plan.

### Apply Job Fails — "Resource already exists"

**Symptom**: Terraform tries to create a resource that already exists.

**Cause**: State drift — the Spaces state file doesn't match the actual DigitalOcean resources. Someone ran `terraform apply` manually, or resources were created through the DigitalOcean console.

**Fix**: Import the existing resource into the state:
```bash
terraform import digitalocean_vpc.network <vpc-id>
```

### Secret Missing Error

**Symptom**: `Error: __${{ secrets.DO_SPACES_BUCKET }}__` appears in logs.

**Fix**: Check GitHub repository → Settings → Secrets and variables → Actions. Ensure all required secrets are defined.

---

## 🔒 Security in the Pipeline

### What the Pipeline Has Access To

The pipeline runs with GitHub Actions' default permissions plus the secrets it inherits:

| Permission | Scope | Used For |
|-----------|-------|---------|
| Read repository code | This repo | `actions/checkout` |
| Write workflow artifacts | This run | Upload/download plan binaries |
| DigitalOcean API (via token) | DigitalOcean account | Create/modify infrastructure |
| Spaces API (via keys) | Specific Spaces bucket | Read/write state files |

### Secret Protection

1. **Secrets are never printed** — GitHub Actions automatically masks secret values in logs
2. **Secrets are never in code** — No `.tfvars` contains API keys; no `variables.tf` references secrets
3. **Secrets are scoped** — `DIGITALOCEAN_TOKEN` can be scoped to read-write on specific resources
4. **Reusable workflows inherit, not redeclare** — Secrets flow through `secrets: inherit` without being duplicated

### Least Privilege for the Token

The DigitalOcean token should have (at minimum):
- **Write** access to: Droplets, Databases, VPCs, Firewalls, Projects, Spaces
- **Read** access to: Account, Billing (for cost tracking)

> Create a **project-scoped** token in DigitalOcean if possible, limiting the token's blast radius to just the FinTrack project resources.

---

## 📚 Related Documents

| Document | Description |
|----------|-------------|
| [README.md](../readme.md) | Project overview and quick start |
| [architecture.md](architecture.md) | Architecture deep dive |
| [reference-architecture.md](reference-architecture.md) | Enterprise reference patterns |
| [best-practices.md](best-practices.md) | Engineering standards and guidelines |
