# CI/CD Pipeline — Learning GitHub Actions + Terraform Together 🔄

> **If you're new to GitOps or setting up Terraform CI/CD, this is the story of how I learned it — including the 3-hour debugging session that taught me about the "Headless Init Fix."**

---

## Table of Contents

- [GitOps: The One-Sentence Explanation](#-gitops-the-one-sentence-explanation)
- [Pipeline Overview: What Happens When](#-pipeline-overview-what-happens-when)
- [The Three Workflow Files](#-the-three-workflow-files)
- [The Plan-Apply Split (Why Two Phases?)](#-the-plan-apply-split-why-two-phases)
- [Sequential Execution: Why Layers Can't Go Parallel](#-sequential-execution-why-layers-cant-go-parallel)
- [The Headless Init Fix (My 3-Hour Debugging Saga)](#-the-headless-init-fix-my-3-hour-debugging-saga)
- [State Key Strategy: Naming Your Files](#-state-key-strategy-naming-your-files)
- [Plan Binary Artifacts: The Magic of Frozen Plans](#-plan-binary-artifacts-the-magic-of-frozen-plans)
- [Adding a New Spoke to the Pipeline](#-adding-a-new-spoke-to-the-pipeline)
- [Troubleshooting: What I Broke and How I Fixed It](#-troubleshooting-what-i-broke-and-how-i-fixed-it)
- [Security: What the Pipeline Can Access](#-security-what-the-pipeline-can-access)

---

## 🤖 GitOps: The One-Sentence Explanation

**GitOps means Git is the single source of truth. Want to change infrastructure? Edit a file, open a PR, get it reviewed, merge it. The pipeline does the rest.**

Before GitOps, I used to SSH into servers and run commands. Or run `terraform apply` from my laptop. GitOps changed everything:

1. **All changes go through Git** — no more "I ran this command on my machine and it worked" nonsense
2. **PRs create a paper trail** — every change has a review, a discussion, and a plan output
3. **The pipeline is the enforcer** — it checks formatting, validates syntax, runs a plan, and only applies when you merge
4. **No manual applies** — never again will I run `terraform apply` in production from a terminal

Here's the flow:

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

## 📐 Pipeline Overview: What Happens When

### When the Pipeline Triggers

The pipeline has two trigger events:

| Event | Branch | Watched Paths | What Happens |
|-------|--------|---------------|-------------|
| Pull Request | main | `Workload/Spokes/fintrack/**` or `Deployment/Spokes/fintrack/**` | Runs `terraform plan` — shows what would change |
| Push | main | Same paths | Runs `terraform apply` — executes the plan |

> **Path filtering**: Changes to `Docs/`, `README.md`, or other non-infrastructure files DON'T trigger the pipeline. I learned this after seeing 10 pipeline runs for documentation typos.

### The Pipeline at a Glance

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

## 📁 The Three Workflow Files

### 1. `fintrack-pipeline.yml` — The Orchestrator

This is the **main workflow**. It decides:
- **When** to run (PR to main, Push to main)
- **Which** files trigger it (path filters)
- **The order** of jobs (via `needs:` dependencies)
- **Which** reusable workflow to call for each job

```yaml
# Simplified structure
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
    needs: plan-network   # ← This is how I enforce order
    uses: ./.github/workflows/terraform-plan.yml
    # ... different working_directory and state_key
    secrets: inherit

  # ... and so on for plan-identity, apply-network, etc.
```

> 💡 **Insight**: The `needs:` keyword is what creates the sequential chain. `plan-data` won't start until `plan-network` finishes successfully. This is critical because `plan-data` reads state produced by the network layer.

### 2. `terraform-plan.yml` — The Reusable Plan Workflow

This is called 3 times (once per layer) during the PR phase. It handles:

1. **Checkout** — Pull the code from the PR branch
2. **Setup Terraform** — Install Terraform 1.5.7
3. **Format Check** — `terraform fmt -check` ensures consistent style
4. **Init** — Initialize with backend config (this is where the Headless Init Fix lives)
5. **Validate** — `terraform validate` checks syntax
6. **Plan** — `terraform plan -out=tfplan` creates the execution plan binary
7. **Upload Artifact** — Save the plan binary for the apply stage

```yaml
# Key inputs the caller must provide:
inputs:
  working_directory:  # e.g., "Workload/Spokes/fintrack/network"
  tfvars_file:        # Path to .tfvars from working directory
  state_key:          # State file path, e.g., "spokes/fintrack/network.tfstate"
  artifact_name:      # Unique name for plan artifact
```

### 3. `terraform-apply.yml` — The Reusable Apply Workflow

Called 3 times (once per layer) during the merge phase. It handles:

1. **Checkout** — Pull main branch
2. **Setup Terraform** — Same version as plan
3. **Init** — Same backend configuration (must match exactly)
4. **Download Artifact** — Fetch the plan binary from the PR
5. **Apply** — `terraform apply tfplan` — executes the pre-compiled plan

**Key difference from plan**: No `fmt -check`, no `validate`, no `plan`. Just init → download → apply. The plan was already validated during the PR phase.

---

## 🔄 The Plan-Apply Split (Why Two Phases?)

### Why Not Just Run `terraform apply` Directly?

I learned this the hard way after accidentally destroying a resource. The Plan-Apply split is a **safety gate**:

| Reason | What It Prevents |
|--------|-----------------|
| **Review before execution** | You see the plan output in the PR before anything happens |
| **Consistency guarantee** | The exact same plan binary is used in apply — no drift |
| **Audit trail** | Every change has a recorded plan attached to a PR |
| **Rollback opportunity** | You can close the PR and nothing was ever applied |
| **Least privilege** | PR workflow only needs read access; merge workflow needs write access |

### How the Plan Binary Works

Here's the magic: The plan binary (`tfplan`) is a **snapshot of exactly what will be created**. It includes:

- The complete Terraform configuration at plan time
- The current state file contents
- The execution graph (what creates, modifies, or destroys)
- All variable values that were passed

```bash
# PR phase: create the plan
terraform plan -out=tfplan
# → Uploads tfplan as an artifact called "fintrack-network-tfplan"

# Merge phase: use the exact same plan
terraform apply tfplan
# → Guaranteed to do exactly what was in the PR's plan output
```

> 🔑 **This is the killer feature**: Even if someone pushes to `main` between the PR review and the merge, the apply uses the plan from the PR — not the current state of `main`. What you reviewed is what gets applied, period.

---

## 📋 Sequential Execution: Why Layers Can't Go Parallel

### The Dependency Chain

The layers have **hard dependencies** — each one needs data from the one before it:

| Layer | Needs Output From |
|-------|------------------|
| Spoke Network | Core Network (hub_vpc_id) |
| Spoke Data | Spoke Network (spoke_vpc_id) |
| Spoke Identity | Spoke Network (droplet_urns) + Spoke Data (database_urn) |

These are enforced via `needs:` in GitHub Actions:

```yaml
plan-network:
  # No needs — first in sequence

plan-data:
  needs: plan-network      ← Wait for network plan

plan-identity:
  needs: plan-data          ← Wait for data plan
```

### What I Learned About Dependencies

If all three layers ran in parallel:
- **Spoke Data** would fail (can't find spoke VPC state — it doesn't exist yet)
- **Spoke Identity** would fail (can't find droplet or DB state)
- I'd waste 3-10 minutes on failed jobs

So the pipeline runs in lockstep: one layer at a time. It takes about 55 seconds for all three plans and 220 seconds (~4 min) for all three applies.

---

## 🧠 The Headless Init Fix (My 3-Hour Debugging Saga)

This was the single most frustrating issue I hit, and it's the one I want every future reader to avoid.

### The Problem

I was using partial S3 backend configuration — the `backend.tf` file just says `backend "s3" {}` with no values. The real config comes from CI flags:

```hcl
# backend.tf — intentionally empty
terraform {
  backend "s3" {}
}
```

This is the standard pattern for keeping secrets out of code. But when I ran this in GitHub Actions, `terraform init` would just **hang**. No output. No error. Just silence until the job timed out.

### Why It Happened

The AWS S3 driver (which Terraform uses under the hood for S3-compatible backends) requires a `region` parameter. Without it, Terraform prompts interactively:

```
$ terraform init
Initializing the backend...

region
  AWS region of the S3 Bucket and DynamoDB Table (if used).

  Enter a value: _
```

In a headless CI environment, there's no one to type a value. So it just... waits. Forever.

### The Fix

Inject `region=us-east-1` at init time:

```yaml
- name: Terraform Init
  run: |
    terraform init \
      -backend-config="bucket=${{ secrets.DO_SPACES_BUCKET }}" \
      -backend-config="endpoint=https://sgp1.digitaloceanspaces.com" \
      -backend-config="key=${{ inputs.state_key }}" \
      -backend-config="access_key=${{ secrets.DO_SPACES_ACCESS_KEY }}" \
      -backend-config="secret_key=${{ secrets.DO_SPACES_SECRET_KEY }}" \
      -backend-config="region=us-east-1"    # ← THIS LINE SAVES YOU
```

### Why `us-east-1`?

DigitalOcean Spaces doesn't use AWS region names. The endpoint URL (`sgp1.digitaloceanspaces.com`) determines where you're connecting. The `region` value is ONLY needed to satisfy the AWS SDK's internal validation. `us-east-1` is a safe dummy value that:

- Passes the SDK's format validation
- Doesn't affect connectivity (the endpoint URL controls that)
- Works regardless of which Spaces region you're using

> 📝 **I documented this in the CI/CD pipeline as the "Headless Init Fix" because I want my future self (and you) to never waste 3 hours on this again.**

---

## 🔑 State Key Strategy: Naming Your State Files

### The Convention

Each layer's state file has a predictable key:

```
{layer}/{module}.tfstate
```

| State Key | What It Stores |
|-----------|---------------|
| `core/network.tfstate` | Hub VPC |
| `core/identity.tfstate` | Hub Project |
| `spokes/fintrack/network.tfstate` | FinTrack Droplets + Firewall |
| `spokes/fintrack/data.tfstate` | FinTrack MongoDB |
| `spokes/fintrack/identity.tfstate` | FinTrack Project binding |

### Why This Convention?

1. **Namespacing** — `core/` vs `spokes/` prevents accidental collisions between hub and spoke
2. **Grouping** — All files for one app are under `spokes/{app}/`
3. **Scalability** — Adding `spokes/payments/network.tfstate` is trivial
4. **Consistency** — Mirrors the directory structure (`Workload/Spokes/fintrack/network`)

### The Gotcha I Hit

**Make sure your pipeline state keys match your `data.tf` references.**

I had the pipeline writing state to `core/network.tfstate`, but my Core Identity's `data.tf` was reading from `core/network/global.tfstate`. Different key = different state = the identity layer couldn't find the VPC.

**Fix**: Align everything to the same key convention. I standardized on the flat format (`core/network.tfstate`) everywhere.

---

## 📦 Plan Binary Artifacts: The Magic of Frozen Plans

### What Gets Uploaded

Each plan job produces a `tfplan` file — about 18KB for small configurations:

```bash
$ ls -la tfplan
-rw-r--r-- 1 root root 18432 ... tfplan
```

### Artifact Naming

```
{app}-{layer}-tfplan
```

| Artifact Name | Content |
|---------------|---------|
| `fintrack-network-tfplan` | Plan for the network layer |
| `fintrack-data-tfplan` | Plan for the data layer |
| `fintrack-identity-tfplan` | Plan for the identity layer |

### Retention: 1 Day

```yaml
- uses: actions/upload-artifact@v4
  with:
    retention-days: 1    # ← Plans expire after 1 day
```

**Why only 1 day?**
- PRs are usually reviewed within 24 hours
- Plans become invalid if someone pushes new commits to the branch
- Keeps storage costs on GitHub low

> If a PR stays open longer than a day, push a new commit to re-trigger the pipeline and get a fresh plan.

### How Apply Uses the Artifact

```yaml
- name: Download Plan Artifact
  uses: actions/download-artifact@v4
  with:
    name: ${{ inputs.artifact_name }}
    path: ${{ inputs.working_directory }}

- name: Terraform Apply
  run: terraform apply -input=false tfplan  # ← Uses exact same binary
```

---

## ➕ Adding a New Spoke to the Pipeline

If I wanted to add a "payments" app alongside FinTrack, here's what I'd do:

**1. Create workload directories** (same pattern as `fintrack`):
```
Workload/Spokes/payments/
├── network/
├── data/
└── identity/
```

**2. Create deployment config**:
```
Deployment/Spokes/payments/dev.tfvars
```

**3. Add pipeline jobs** — 3 plan jobs and 3 apply jobs, identical pattern but with different paths and names:

```yaml
plan-payments-network:
  if: github.event_name == 'pull_request'
  uses: ./.github/workflows/terraform-plan.yml
  with:
    working_directory: 'Workload/Spokes/payments/network'
    tfvars_file: '../../../../Deployment/Spokes/payments/dev.tfvars'
    state_key: 'spokes/payments/network.tfstate'
    artifact_name: 'payments-network-tfplan'
  secrets: inherit
```

**4. Update path filters** so the pipeline triggers on payments changes too.

---

## 🔧 Troubleshooting: What I Broke and How I Fixed It

### Pipeline Doesn't Trigger

**Symptom**: Push code, no workflow runs.

**Checklist**:
1. Are the changed files in the watched paths? (`Workload/Spokes/fintrack/**`)
2. Is the branch correct? PR → main, push → main
3. Is GitHub Actions enabled for the repo?
4. Any workflow syntax errors? Check the GitHub Actions tab

### Plan Job Fails — "No works found"

I spent 20 minutes debugging this once. The `tfvars_file` path is **relative to the working directory**, not the repo root:

```yaml
# From Workload/Spokes/fintrack/network, go up 4 levels to find dev.tfvars:
tfvars_file: '../../../../Deployment/Spokes/fintrack/dev.tfvars'
```

Count the directories: `Workload/Spokes/fintrack/network` → up to `Workload/Spokes/fintrack` → up to `Workload/Spokes` → up to `Workload` → up to root → then down to `Deployment/Spokes/fintrack/dev.tfvars`. That's `../../../../`.

### Init Hangs Forever

**Fix**: Add `-backend-config="region=us-east-1"`. See the Headless Init Fix section above.

### Apply Fails — "Plan file was created by a different process"

**Causes**:
1. Someone force-pushed to `main` between plan and merge
2. The plan artifact expired (1-day retention)
3. The workflow was re-run from a different commit

**Fix**: Close and re-open the PR (or push a new commit) to generate a fresh plan.

### Apply Fails — "Resource already exists"

**Cause**: Someone ran `terraform apply` manually, or created resources via the DO console. State drift.

**Fix**: Import the existing resource into state:
```bash
terraform import digitalocean_vpc.network <vpc-id>
```

### Secret Missing — `__${{ secrets.DO_SPACES_BUCKET }}__`

Literally the raw template string appears in logs.

**Fix**: Check GitHub → Settings → Secrets and variables → Actions. Make sure `DO_SPACES_BUCKET` is defined.

---

## 🔒 Security: What the Pipeline Can Access

The pipeline runs with GitHub Actions' permissions plus secrets:

| Permission | Scope |
|-----------|-------|
| Read repository code | This repo |
| Write workflow artifacts | This workflow run |
| DigitalOcean API | Full access (via `DIGITALOCEAN_TOKEN`) |
| Spaces API | Read/write to your bucket (via access keys) |

### Secret Protection

1. **Secrets are never printed** — GitHub Actions automatically masks them in logs
2. **Secrets are never in code** — No `.tfvars` contains API keys
3. **Reusable workflows inherit, not redeclare** — `secrets: inherit` passes all secrets without duplicating them

### Least Privilege Tip

Create a **project-scoped** DigitalOcean token that only has access to the resources in this project. That way, even if the token leaks, the blast radius is limited.

---

## 📚 Related Docs

| Document | What It Covers |
|----------|---------------|
| [README.md](../readme.md) | Project overview, what I learned, getting started |
| [architecture.md](architecture.md) | Hub-and-spoke, state bridges, module design |
| [reference-architecture.md](reference-architecture.md) | Ways to extend: multi-spoke, multi-region, cost estimates |
| [best-practices.md](best-practices.md) | Lessons learned the hard way |
