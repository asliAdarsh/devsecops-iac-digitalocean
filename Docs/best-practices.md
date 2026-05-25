# Best Practices — Lessons I Learned the Hard Way 🛠️

> **Every rule in this doc is here because I broke it, regretted it, and fixed it.** If you're learning Terraform and IaC, this is the stuff I wish someone had told me before I started.

---

## Table of Contents

- [Infrastructure as Code: What I Wish I Knew](#-infrastructure-as-code-what-i-wish-i-knew)
- [Repository Hygiene: Keep It Clean](#-repository-hygiene-keep-it-clean)
- [Module Design: Don't Make My Mistakes](#-module-design-dont-make-my-mistakes)
- [State Management: Handle With Care](#-state-management-handle-with-care)
- [Secrets & Security: What I Almost Committed](#-secrets--security-what-i-almost-committed)
- [CI/CD Pipeline: Rules I Now Live By](#-cicd-pipeline-rules-i-now-live-by)
- [Code Review Checklist (For Terraform PRs)](#-code-review-checklist-for-terraform-prs)
- [Naming Conventions: Pick One and Stick to It](#-naming-conventions-pick-one-and-stick-to-it)
- [Operational Runbooks: What I Do Daily/Weekly](#-operational-runbooks-what-i-do-dailyweekly)
- [Environment Cleanup: How to Tear Down Safely](#-environment-cleanup-how-to-tear-down-safely)

---

## 🏗️ Infrastructure as Code: What I Wish I Knew

### 1. `terraform fmt` Is Not Optional

I used to skip formatting. "It works, who cares about spaces?" Then CI started rejecting my PRs. Then I had to review my own messy code. Now I run this constantly:

```bash
terraform fmt -recursive
```

Do it before every commit. The `-check` flag in CI will reject unformatted code, so just get in the habit.

> ⚠️ **Lesson**: If `terraform fmt -check` fails in CI, the entire plan job fails. You waste 2 minutes of CI time for a missing space.

### 2. Follow the Six-File Pattern

Every workload directory should have exactly these files:

| File | Purpose |
|------|---------|
| `providers.tf` | Terraform version & provider config |
| `backend.tf` | State storage config (partial) |
| `variables.tf` | Input variables |
| `data.tf` | Remote state reads |
| `main.tf` | Module calls |
| `outputs.tf` | Exposed values |

Why? Because after the 5th time looking for where variables are defined, you'll appreciate consistency. Every directory looks the same. No surprises.

### 3. Pin Your Versions

```hcl
# providers.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.39.0"  # ← Major.minor pinned, patch updates allowed
    }
  }
}
```

Without pinning, a provider update can change behavior unexpectedly. `~> 2.39.0` means "any version from 2.39.0 up to but not including 2.40.0" — safe patch updates only.

### 4. Write Descriptions for Every Variable

```hcl
# ✅ Good — I know exactly what this is for
variable "private_network_uuid" {
  type        = string
  description = "The private VPC network identifier where this database cluster will be isolated."
}

# ❌ Bad — I wrote this at 2am and now I have no idea
variable "network" {
  type = string
}
```

Descriptions show up in `terraform plan` output and in generated docs. Your future self will thank you.

### 5. Defaults Should Be Dev-Friendly

```hcl
variable "node_count" {
  type        = number
  description = "Number of database nodes. Use 1 for dev, 3 for production HA."
  default     = 1  # ← Cheap by default, override for production
}
```

Someone cloning the repo should be able to run `terraform apply` and get a working dev environment without passing a single variable.

---

## 🧹 Repository Hygiene: Keep It Clean

### 1. Never Commit State Files or Plans

```gitignore
*.tfstate
*.tfstate.backup
*.tfplan
.terraform/
```

**Why?** State files contain sensitive info (resource IDs, IPs, sometimes secrets). Plans are large binaries that change constantly. Neither belongs in Git.

### 2. Keep `.tfvars` Out... But Not ALL of Them

Our `.tfvars` files (in `Deployment/`) contain only non-sensitive values like instance counts and region names. They're safe to commit.

**But** — if any `.tfvars` file ever needs to contain a secret value (like a database password), add `*.tfvars` to `.gitignore` immediately and switch to a secrets manager.

### 3. Use Conventional Commits

| Prefix | When to Use | Example |
|--------|------------|---------|
| `feat:` | New module, resource, or feature | `feat: add autoscaling module` |
| `fix:` | Bug fix | `fix: correct firewall outbound port` |
| `refactor:` | No behavior change | `refactor: extract common variables` |
| `docs:` | Documentation only | `docs: add architecture diagram` |
| `chore:` | Tooling, CI/CD | `chore: update Terraform to 1.6.0` |

> 📝 **I didn't do this from the start**, and now I have commit history that says "fix stuff" and "update." Don't be like me.

---

## 📦 Module Design: Don't Make My Mistakes

### 1. One Module = One Thing

| ✅ Correct | ❌ Wrong |
|-----------|---------|
| `Modules/droplet` — creates droplets | `Modules/compute` — creates droplets + firewalls + DNS |
| `Modules/firewall` — creates firewall rules | `Modules/security` — creates firewall + projects + SSH keys |

A module that does one thing is easy to test, reuse, and reason about. A module that does everything is a maintenance nightmare.

### 2. Clean Input Contracts

```hcl
# ✅ Good — minimum viable inputs
variable "vpc_name"  { type = string }
variable "region"    { type = string }
variable "cidr_range" { type = string }

# ❌ Bad — too many inputs that the module doesn't even use
variable "vpc_name"      { type = string }
variable "region"        { type = string }
variable "cidr_range"    { type = string }
variable "environment"   { type = string }   # ← Unused!
variable "tags"          { type = map(string) }  # ← Unused!
```

Don't add variables "just in case." Add them when you need them.

### 3. Output Only What's Needed Downstream

```hcl
# ✅ Good — only what downstream layers need
output "vpc_id" {
  value       = digitalocean_vpc.network.id
  description = "The unique network identifier passed to downstream compute grids."
}

# ❌ Bad — exposing internals
output "vpc_self_link"    { value = "..." }   # Nobody uses this
output "vpc_create_time"  { value = "..." }   # Not actionable
```

**My specific lesson**: I originally only output `vpc_id` from the networking module. But the Identity layer needed `vpc_urn` for project resource binding. I had to add a second output later. Think about who consumes your outputs.

### 4. Don't Hardcode Environment Values in Modules

```hcl
# ✅ Good — environment is a variable passed by the caller
resource "digitalocean_database_cluster" "mongodb_cluster" {
  size  = var.size_slug
  tags  = ["database", var.environment]
}

# ❌ Bad — hardcoded to dev, fails in production
resource "digitalocean_database_cluster" "mongodb_cluster" {
  size  = "db-s-1vcpu-1gb"   # ← Can't change without editing the module
  tags  = ["database", "dev"]  # ← Wrong in production!
}
```

### 5. Use Tags for Resource Identification

```hcl
resource "digitalocean_droplet" "vm" {
  tags = var.tags
}
```

Tags should include at minimum:
- Application name (`fintrack`, `payments`)
- Environment (`dev`, `staging`, `prod`)
- Any team or cost-center identifiers

---

## 🔐 State Management: Handle With Care

### 1. One State Per Layer

| ❌ What Not to Do | ✅ What to Do |
|---|---|
| One state file for everything | Separate state per layer |
| `terraform.tfstate` in Git | State in DigitalOcean Spaces |
| Workspaces for environment separation | Separate Spaces key paths |

### 2. Always Use Partial Backend Config

```hcl
# backend.tf — Keep this EMPTY
terraform {
  backend "s3" {}  # ← No values here!
}
```

Bucket names, keys, and credentials are injected at `terraform init` time via CLI flags. Nothing sensitive in the codebase.

### 3. Pass Backend Config via CLI, Not Files

```bash
# ✅ Good — current approach
terraform init \
  -backend-config="bucket=${{ secrets.DO_SPACES_BUCKET }}" \
  -backend-config="key=spokes/fintrack/network.tfstate"

# ❌ Bad — commits secrets to repo
terraform init -backend-config=backend-config.hcl
```

### 4. Always Include the Dummy Region

Every `terraform init` with DigitalOcean Spaces MUST include:

```bash
-backend-config="region=us-east-1"
```

This satisfies the AWS S3 SDK's internal validation. Without it, `terraform init` hangs in CI (learned that one the hard way — see the [ci-cd-pipeline.md](ci-cd-pipeline.md) for the full saga).

### 5. Never Manually Edit State Files

State files are binary data. Editing them breaks Terraform's ability to manage resources. If you need to fix state:

| Command | What It Does |
|---------|-------------|
| `terraform state mv` | Rename or move a resource in state |
| `terraform state rm` | Remove a resource from state (without destroying it) |
| `terraform import` | Add an existing resource to state |

### 6. Enable Spaces Versioning on Your Bucket

This is a checkbox in the DigitalOcean Spaces settings. It gives you:
- Automatic backup on every state write
- Point-in-time recovery if state gets corrupted
- Audit trail of every state change

---

## 🔒 Secrets & Security: What I Almost Committed

### 1. Zero Secrets in Code

| ❌ Never Commit | ✅ Do This Instead |
|---|---|
| `DIGITALOCEAN_TOKEN = "dop_v1_..."` | Store in GitHub Secrets, pass as env var |
| `access_key = "DO00ABC123"` | Inject via `-backend-config` at runtime |
| Database passwords in `.tfvars` | Use Terraform's `random_password` + DO managed DB |

### 2. Use Environment Variables for Provider Auth

```hcl
# providers.tf — no token here
provider "digitalocean" {}  # ← Reads DIGITALOCEAN_TOKEN from environment
```

```yaml
# In CI:
env:
  DIGITALOCEAN_TOKEN: ${{ secrets.DIGITALOCEAN_TOKEN }}
```

### 3. Least Privilege for Tokens

Create a **project-scoped** DigitalOcean token (not a full account token) that can only access:
- The resources in your project
- Spaces (for state storage)

**Rotate tokens every 90 days.** Set a calendar reminder.

### 4. Firewall: Restrict SSH in Production

```hcl
# Dev: 0.0.0.0/0 is fine for learning
# Production: Restrict to your VPN
inbound_rule {
  protocol         = "tcp"
  port_range       = "22"
  source_addresses = ["10.0.0.0/8", "203.0.113.0/24"]  # ← Your VPN range
}
```

### 5. Database: Private Network Only

Already enforced in this project — the MongoDB cluster has no public endpoint. This is non-negotiable for anything beyond a sandbox.

---

## 🔄 CI/CD Pipeline: Rules I Now Live By

### 1. Plan-Apply Split is Non-Negotiable

| Phase | When | What |
|-------|------|------|
| Plan | On PR | `terraform plan -out=tfplan` → upload artifact |
| Apply | On merge to main | `terraform apply tfplan` using the exact same binary |

- **Never** combine plan and apply in one step
- **Never** run `terraform apply` from your local machine for shared environments

### 2. Always Upload Plans as Artifacts

```yaml
- name: Upload Plan Artifact
  uses: actions/upload-artifact@v4
  with:
    name: fintrack-network-tfplan
    path: ${{ inputs.working_directory }}/tfplan
    retention-days: 1
```

The plan binary guarantees that **what was reviewed is what gets applied**.

### 3. Sequential Jobs for Dependent Layers

```yaml
plan-network:
  # ...
plan-data:
  needs: plan-network    # ← REQUIRED
plan-identity:
  needs: plan-data       # ← REQUIRED
```

Running dependent layers in parallel causes guaranteed failures because upstream state doesn't exist yet.

### 4. Use `secrets: inherit`

```yaml
jobs:
  plan-network:
    uses: ./.github/workflows/terraform-plan.yml
    secrets: inherit  # ← Passes all repo secrets automatically
```

Cleaner than redeclaring each secret in `workflow_call` inputs.

### 5. Path-Trigger Only What's Needed

```yaml
on:
  pull_request:
    paths:
      - 'Workload/Spokes/fintrack/**'
      - 'Deployment/Spokes/fintrack/**'
```

Don't trigger the pipeline for `Docs/` or `README.md` changes. I wasted hours watching pipeline runs for documentation typos.

---

## 👁️ Code Review Checklist (For Terraform PRs)

When reviewing a Terraform PR (even your own), check:

**Correctness**
- [ ] Does the `plan` output match what the PR says should happen?
- [ ] Any unexpected resource **destructions**? (Look for `-` signs in the plan)
- [ ] Are variable types correct? (string vs number vs list)
- [ ] Are `needs:` dependencies correctly ordered?

**Security**
- [ ] Any hardcoded secrets or tokens?
- [ ] Are firewall rules appropriately restrictive?
- [ ] Is the database on a private network?
- [ ] Are secrets passed via env vars, not in code?

**Consistency**
- [ ] Six-file pattern followed? (main, variables, outputs, data, providers, backend)
- [ ] `terraform fmt -recursive` has been run?
- [ ] Naming conventions followed?
- [ ] Variable descriptions are informative?

**Architecture**
- [ ] Does the change respect layer boundaries? (Network doesn't touch data state, etc.)
- [ ] Are modules reused rather than duplicated?
- [ ] Are environment-specific values in `.tfvars` (not hardcoded)?

### Common Review Comments I Give Myself

| Issue | Comment I Write |
|-------|----------------|
| Missing `terraform fmt` | "Run `terraform fmt -recursive` and recommit." |
| Hardcoded value | "This goes in `.tfvars`, not hardcoded." |
| Missing variable description | "Add a description to this variable." |
| Module does too much | "This module should do one thing. Split it up." |
| Direct resource instead of module | "We have a module for this in `Modules/`. Reuse it." |

---

## 🏷️ Naming Conventions: Pick One and Stick to It

I standardized on these after 3 refactors. Pick a convention and DON'T change it mid-project.

### Resource Naming

| Resource | Pattern | Example |
|----------|---------|---------|
| VPC | `{project}-{env}-vpc` | `fintrack-dev-vpc` |
| Droplet | `{app}-{env}` or `{app}-{env}-node-{n}` | `fintrack-dev` or `fintrack-dev-node-1` |
| Firewall | `{app}-{env}-firewall` | `fintrack-dev-firewall` |
| DB Cluster | `{app}-{env}-{engine}` | `fintrack-dev-mongodb` |
| Project (DO) | `{App}-{Env}-Workspace` | `FinTrack-Dev-Workspace` |

### File & Directory Naming

| Item | Convention | Example |
|------|-----------|---------|
| Directories | `kebab-case` | `Workload/Spokes/fintrack/` |
| Module dirs | `snake_case` | `Modules/data/mongo_db/` |
| Terraform files | `snake_case` | `main.tf`, `variables.tf` |
| Variable names | `snake_case` | `droplet_size`, `instance_count` |
| State keys | `kebab-case` | `spokes/fintrack/network.tfstate` |

### Git Branch Naming

```
feature/{description}       → feature/add-autoscaling
fix/{description}           → fix/firewall-ssh-port
chore/{description}         → chore/update-terraform-version
docs/{description}          → docs/add-contributing-guide
```

---

## 🏃 Operational Runbooks: What I Do Daily/Weekly

### Daily

```bash
# Check pipeline status
# → GitHub Actions tab → Recent workflows

# Check plan output for open PRs
# → PR page → Checks tab → Terraform Plan step

# Quick infrastructure health check
# → DigitalOcean dashboard
```

### Weekly

```bash
# Review DigitalOcean billing for unexpected costs
# → DO Control Panel → Billing

# Check for Terraform/provider updates
# → GitHub Dependabot (if enabled)

# Verify state file backups (Spaces versioning)
# → DO Spaces → Bucket → File version history
```

### Incident Response

| Incident | What I Do |
|----------|-----------|
| Apply failure | Check logs, fix code, re-run |
| Resource deleted by accident | Check state + apply to recreate |
| State file corrupted | Restore from Spaces versioning |
| High costs | Review resources, downsize if needed |

---

## 🧹 Environment Cleanup: How to Tear Down Safely

Destroy order matters. **Always destroy in reverse order of creation:**

```bash
# Step 1: Spoke Identity (project binding — no resources, just references)
cd Workload/Spokes/fintrack/identity
terraform destroy -var-file=../../../../Deployment/Spokes/fintrack/dev.tfvars

# Step 2: Spoke Data (MongoDB — droplets can still exist)
cd ../data
terraform destroy -var-file=../../../../Deployment/Spokes/fintrack/dev.tfvars

# Step 3: Spoke Network (droplets + firewall — last spoke layer)
cd ../network
terraform destroy -var-file=../../../../Deployment/Spokes/fintrack/dev.tfvars

# Step 4: Hub Identity
cd Workload/Core/identity
terraform destroy -var-file=../../../Deployment/Core/global.tfvars

# Step 5: Hub Network (VPC) — ALWAYS LAST!
cd ../network
terraform destroy -var-file=../../../Deployment/Core/global.tfvars
```

> ⚠️ **Why this order matters**: If you destroy the Hub VPC while droplets or MongoDB still reference it, those resources become **orphaned** — they still exist in DigitalOcean but Terraform can't manage them anymore. You'd have to manually clean them up through the DO console.

---

## 📚 Related Docs

| Document | What It Covers |
|----------|---------------|
| [README.md](../readme.md) | Project overview, what I learned, getting started |
| [architecture.md](architecture.md) | Hub-and-spoke, state bridges, module design |
| [ci-cd-pipeline.md](ci-cd-pipeline.md) | GitOps pipeline, Headless Init Fix, troubleshooting |
| [reference-architecture.md](reference-architecture.md) | Ways to extend, cost estimates, production hardening |
