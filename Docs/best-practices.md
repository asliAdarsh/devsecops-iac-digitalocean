# Best Practices

> **Audience**: All contributors — developers, DevOps engineers, platform engineers, and reviewers. These practices ensure the repository remains maintainable, secure, and consistent.

---

## Table of Contents

- [Infrastructure as Code Standards](#-infrastructure-as-code-standards)
- [Repository Hygiene](#-repository-hygiene)
- [Terraform Module Design](#-terraform-module-design)
- [State Management](#-state-management)
- [Secrets & Security](#-secrets--security)
- [CI/CD Pipeline Standards](#-cicd-pipeline-standards)
- [Code Review Guidelines](#-code-review-guidelines)
- [Naming Conventions](#-naming-conventions)
- [Error Handling & Resilience](#-error-handling--resilience)
- [Documentation Standards](#-documentation-standards)
- [Operational Runbooks](#-operational-runbooks)

---

## 📐 Infrastructure as Code Standards

### 1. Always Use `terraform fmt`

Every Terraform file must be formatted with `terraform fmt` before committing. This ensures consistent indentation, alignment, and syntax spacing.

```bash
# Format all Terraform files recursively
terraform fmt -recursive

# CI also checks this:
# name: Terraform Format Check
# run: terraform fmt -check
```

> ⚠️ If `terraform fmt -check` fails in CI, the plan job fails. Fix formatting and push again.

### 2. One Resource Type Per File (Logical Grouping)

| File | Contents |
|------|----------|
| `main.tf` | Module calls and primary resource definitions |
| `variables.tf` | All input variable declarations |
| `outputs.tf` | All output value declarations |
| `data.tf` | `terraform_remote_state` data sources |
| `providers.tf` | Provider and Terraform version constraints |
| `backend.tf` | State backend configuration (partial) |

> **Exception**: Small modules (like `Modules/firewall`) may combine resources in `main.tf` since there's only one resource type.

### 3. Pin Provider and Terraform Versions

```hcl
# providers.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.39.0"  # ← Pin major.minor, allow patch
    }
  }
}
```

- Pinning prevents unexpected behavior from provider upgrades
- `~> 2.39.0` means `>= 2.39.0` and `< 2.40.0` — safe patch updates only
- Review provider version bumps separately via PR

### 4. Use Descriptive Variable Descriptions

```hcl
# ✅ Good
variable "private_network_uuid" {
  type        = string
  description = "The private VPC network identifier where this database cluster will be isolated."
}

# ❌ Bad
variable "network" {
  type = string
}
```

Descriptions become documentation in `terraform plan` output and generated docs.

### 5. Set Sensible Defaults

```hcl
# ✅ Good — defaults for dev environment
variable "node_count" {
  type        = number
  description = "Number of database nodes. Use 1 for dev, 3 for production HA."
  default     = 1
}

variable "size_slug" {
  type        = string
  description = "Engine size for DB cluster nodes."
  default     = "db-s-1vcpu-1gb"
}
```

Defaults should be **development-friendly** — production overrides them explicitly.

---

## 🧹 Repository Hygiene

### 1. Path Structure Consistency

Every workload directory must follow the **six-file pattern**:

```
Workload/{Layer}/{app-name}/
├── backend.tf       # backend "s3" {} — partial
├── providers.tf     # Version constraints + provider config
├── variables.tf     # Input variables
├── data.tf          # Remote state data sources
├── main.tf          # Module calls
└── outputs.tf       # Exposed outputs
```

### 2. Never Commit State Files or Plans

```gitignore
# .gitignore — already configured
*.tfstate
*.tfstate.backup
*.tfplan
.terraform/
```

State files contain **sensitive information** (resource IDs, IPs, possibly secrets). Plans contain **execution snapshots** that can be large and change rapidly. Neither belongs in Git.

### 3. Keep `.tfvars` Out of Git (if they contain secrets)

The current `.gitignore` does **not** exclude `.tfvars` files. This is **by design** — our `.tfvars` files (in `Deployment/`) contain **only** non-sensitive configuration values like instance counts and region names.

> If any `.tfvars` file ever needs to contain a secret value, add `*.tfvars` to `.gitignore` and switch to a secrets management solution.

### 4. Commit Messages Follow Conventional Commits

| Prefix | Usage | Example |
|--------|-------|---------|
| `feat:` | New module, resource, or feature | `feat: add autoscaling module for droplets` |
| `fix:` | Bug fix | `fix: correct firewall outbound port range` |
| `refactor:` | Code change without behavior change | `refactor: extract common variables into locals` |
| `docs:` | Documentation only | `docs: add architecture diagram to readme` |
| `chore:` | Tooling, CI/CD, non-infra | `chore: update Terraform version to 1.6.0` |
| `infra:` | Infrastructure scaffolding | `infra: add spoke directory for payment-service` |

---

## 📦 Terraform Module Design

### 1. Single Responsibility

Each module should do **one thing** and do it well:

| ✅ Correct | ❌ Incorrect |
|-----------|-------------|
| `Modules/droplet` — creates droplets | `Modules/compute` — creates droplets + firewalls + DNS |
| `Modules/firewall` — creates firewall rules | `Modules/security` — creates firewall + projects + SSH keys |
| `Modules/networking` — creates VPC | `Modules/network` — creates VPC + subnets + VPN + peering |

### 2. Clean Interface Contracts

```hcl
# A module interface should be minimal and clear:

# ✅ Good: minimum viable inputs
variable "vpc_name"  { type = string }
variable "region"    { type = string }
variable "cidr_range" { type = string }

# ❌ Bad: over-specified inputs that limit reusability
variable "vpc_name"  { type = string }
variable "region"    { type = string }
variable "cidr_range" { type = string }
variable "environment" { type = string }          # Unused — module shouldn't care
variable "tags"       { type = map(string) }      # Unused in the resource
variable "description" { type = string }          # DCO VPC doesn't have descriptions
```

### 3. Output What's Needed — No More, No Less

```hcl
# ✅ Good: output only what downstream layers need
output "vpc_id" {
  value       = digitalocean_vpc.network.id
  description = "The unique network identifier passed to downstream compute grids."
}

# ❌ Bad: over-exposing module internals
output "vpc_id"    { value = digitalocean_vpc.network.id }
output "vpc_self_link" { value = "..." }       # Not needed by any consumer
output "vpc_create_time" { value = "..." }     # Not actionable
```

### 4. Don't Hardcode Environment-Specific Values in Modules

```hcl
# ✅ Good: environment is a variable
resource "digitalocean_database_cluster" "mongodb_cluster" {
  size  = var.size_slug           # ← Decided by the caller
  tags  = ["database", var.environment]
}

# ❌ Bad: hardcoded to dev
resource "digitalocean_database_cluster" "mongodb_cluster" {
  size  = "db-s-1vcpu-1gb"       # ← Can't change without editing module
  tags  = ["database", "dev"]    # ← Wrong in production
}
```

### 5. Use Tags for Resource Identification

```hcl
resource "digitalocean_droplet" "vm" {
  tags = var.tags  # ← Pass tags from caller
}
```

Tags should include at minimum:
- Application name (`fintrack`, `payment-service`)
- Environment (`dev`, `staging`, `prod`)
- Any team or cost-center identifiers

---

## 🔐 State Management

### 1. One State Per Layer

| ❌ Anti-Pattern | ✅ Best Practice |
|---|---|
| One state file for everything | Separate state per layer |
| `terraform.tfstate` in Git | State in DigitalOcean Spaces |
| Workspaces as environment separation | Separate Spaces key paths |

### 2. Always Use Partial Backend Configuration

```hcl
# backend.tf — DO NOT fill in values here
terraform {
  backend "s3" {}  # ← Empty — config injected at init time
}
```

This keeps bucket names, keys, and credentials **out of the codebase**.

### 3. Pass Backend Config via Flags, Not Files

```bash
# ✅ Good: CLI flags (current approach)
terraform init \
  -backend-config="bucket=${{ secrets.DO_SPACES_BUCKET }}" \
  -backend-config="key=spokes/fintrack/network.tfstate"

# ❌ Bad: backend config file committed
terraform init -backend-config=backend-config.hcl   # ← commits secrets
```

### 4. Include the Dummy Region Flag

Every `terraform init` command that configures the DigitalOcean Spaces backend **must** include:

```bash
-backend-config="region=us-east-1"
```

This satisfies the AWS S3 SDK validation without affecting Spaces connectivity.

### 5. Never Manually Edit State Files

- State files are **internal Terraform data** — editing them breaks Terraform's ability to manage resources
- If state needs fixing, use `terraform state mv`, `terraform state rm`, or `terraform import`
- For major state surgery, work on a backup copy first

### 6. Regular State Backup

Enable **object versioning** on the Spaces bucket. This provides:
- Automatic backup on every state write
- Point-in-time recovery if state gets corrupted
- Audit trail of state changes

---

## 🔒 Secrets & Security

### 1. Zero Secrets in Code

| ❌ Never Commit | ✅ Instead |
|---|---|
| `DIGITALOCEAN_TOKEN = "dop_v1_..."` | Store in GitHub Secrets, pass as env var |
| `access_key = "DO00ABC123"` | Inject via `-backend-config` at runtime |
| Database passwords in `.tfvars` | Use Terraform's `random_password` + DO managed DB |

### 2. Use Environment Variables for Provider Auth

```hcl
# providers.tf
provider "digitalocean" {}  # ← Reads DIGITALOCEAN_TOKEN from env
```

```yaml
# In CI:
env:
  DIGITALOCEAN_TOKEN: ${{ secrets.DIGITALOCEAN_TOKEN }}
```

### 3. Least Privilege for Tokens

The DigitalOcean token should have only the permissions it needs:

- **Droplets**: Create, read, update, delete
- **Databases**: Create, read, update, delete
- **VPC**: Create, read, update, delete
- **Firewalls**: Create, read, update, delete
- **Projects**: Create, read, update, delete
- **Spaces**: Read, write (for state storage only)

> In DigitalOcean, create a **project-scoped token** rather than a full-account token when possible.

### 4. Firewall Best Practices

```hcl
# Production: Restrict SSH to VPN/CIDR
inbound_rule {
  protocol         = "tcp"
  port_range       = "22"
  source_addresses = ["10.0.0.0/8", "203.0.113.0/24"]  # ← VPN range
}

# Production: Drop HTTP, force HTTPS
# (Don't include port 80 in production if you redirect at the app level)
```

### 5. Never Use Root Tokens

- Create a **dedicated service account** for CI/CD in DigitalOcean
- Use **project-scoped tokens** not full account tokens
- Rotate tokens **every 90 days** (set a calendar reminder)

---

## 🔄 CI/CD Pipeline Standards

### 1. Plan-Apply Separation is Non-Negotiable

| Phase | When | What | Who Sees Output |
|-------|------|------|----------------|
| Plan | On PR | `terraform plan -out=tfplan` | PR reviewers |
| Apply | On merge | `terraform apply tfplan` | Pipeline logs |

- **Never** combine plan and apply in a single step
- **Never** allow direct `terraform apply` from local machines for shared environments

### 2. Always Upload Plans as Artifacts

```yaml
- name: Upload Plan Artifact
  uses: actions/upload-artifact@v4
  with:
    name: fintrack-network-tfplan
    path: ${{ inputs.working_directory }}/tfplan
    retention-days: 1
```

The plan binary ensures that **what was reviewed is what gets applied**.

### 3. Sequential Job Dependencies

```yaml
jobs:
  plan-network:
    # ...
  plan-data:
    needs: plan-network  # ← Required
  plan-identity:
    needs: plan-data     # ← Required
```

Parallel execution of dependent layers causes **guaranteed failures** because the upstream state won't exist yet.

### 4. Use `secrets: inherit` for Reusable Workflows

```yaml
jobs:
  plan-network:
    uses: ./.github/workflows/terraform-plan.yml
    secrets: inherit  # ← Passes all repository secrets automatically
```

This is cleaner than redeclaring each secret in the `workflow_call` inputs.

### 5. Path-Trigger Only What's Needed

```yaml
on:
  pull_request:
    paths:
      - 'Workload/Spokes/fintrack/**'      # Only trigger on spoke changes
      - 'Deployment/Spokes/fintrack/**'
      - '.github/workflows/**'              # Also trigger on pipeline changes
```

Don't trigger the full pipeline when editing `Docs/`, `README.md`, or other non-infrastructure files.

---

## 👁️ Code Review Guidelines

### Checklist for Reviewers

When reviewing a Terraform PR, check:

**Correctness**
- [ ] Does the `plan` output match what the PR description says should happen?
- [ ] Are there any unexpected resource **destructions**? (Look for `-` signs in the plan)
- [ ] Are the variable types correct? (string vs number vs list)
- [ ] Are dependencies correctly ordered via `needs:` in CI?

**Security**
- [ ] Are there any hardcoded secrets or tokens?
- [ ] Are firewall rules appropriately restrictive? (No `0.0.0.0/0` for SSH in production)
- [ ] Is the database on a private network (no public endpoint)?
- [ ] Are secrets passed via environment variables or GitHub Secrets (not in code)?

**Consistency**
- [ ] Does the code follow the six-file pattern? (main, variables, outputs, data, providers, backend)
- [ ] Has `terraform fmt -recursive` been run?
- [ ] Are naming conventions followed? (kebab-case for most things)
- [ ] Are variable descriptions informative?

**Architecture**
- [ ] Does the change respect layer boundaries? (Network doesn't touch data state, etc.)
- [ ] Are modules reused rather than duplicated?
- [ ] Are environment-specific values in `.tfvars` (not hardcoded)?

### Common Code Review Comments

| Issue | Comment |
|-------|---------|
| Missing `terraform fmt` | "Please run `terraform fmt -recursive` and recommit." |
| Hardcoded value | "This value should go in `dev.tfvars` instead of being hardcoded." |
| Missing variable description | "Please add a description to this variable." |
| Overly complex module | "This module does too much. Consider splitting into smaller modules." |
| Direct resource instead of module | "We have a module for this in `Modules/`. Please reuse it." |
| State key wrong | "The state key should be `spokes/fintrack/network.tfstate`, not `network.tfstate`." |
| Unnecessary whitespace change | "Please revert formatting changes in unrelated files." |

---

## 🏷️ Naming Conventions

### Resource Naming

| Resource Type | Pattern | Example |
|--------------|---------|---------|
| VPC | `{project}-{environment}-vpc` | `fintrack-dev-vpc` |
| Droplet | `{app}-{environment}` or `{app}-{environment}-node-{n}` | `fintrack-dev` or `fintrack-dev-node-1` |
| Firewall | `{app}-{environment}-firewall` | `fintrack-dev-firewall` |
| DB Cluster | `{app}-{environment}-{engine}` | `fintrack-dev-mongodb` |
| Project (DO) | `{App}-{Environment}-Workspace` | `FinTrack-Dev-Workspace` |

### File & Directory Naming

| Item | Convention | Example |
|------|-----------|---------|
| Directories | `kebab-case` | `Workload/Spokes/fintrack/` |
| Module dirs | `snake_case` | `Modules/data/mongo_db/` |
| Terraform files | `snake_case` | `main.tf`, `variables.tf` |
| Pipeline files | `kebab-case` | `terraform-plan.yml` |
| Variable names | `snake_case` | `droplet_size`, `instance_count` |
| Output names | `snake_case` | `hub_vpc_id`, `droplet_urns` |
| State keys | `kebab-case` | `spokes/fintrack/network.tfstate` |
| Artifact names | `kebab-case` | `fintrack-network-tfplan` |

### Git Branch Naming

```text
feature/{description}       → feature/add-autoscaling
fix/{description}           → fix/firewall-ssh-port
chore/{description}         → chore/update-terraform-version
docs/{description}          → docs/add-contributing-guide
```

---

## 🛡️ Error Handling & Resilience

### Terraform Error Prevention

| Practice | Why |
|----------|-----|
| `terraform validate` in CI | Catches syntax errors before plan |
| `terraform plan -out=tfplan` | Creates a deterministic execution plan |
| `-input=false` in apply | Prevents interactive prompts in CI |
| `terraform fmt -check` | Ensures consistent formatting |

### Handling Apply Failures

If `terraform apply` fails mid-way:

```bash
# 1. Check what was created and what failed
# 2. Fix the issue (e.g., quota exceeded, naming conflict)
# 3. Re-run: terraform apply (Terraform picks up from where it left off)
# 4. If state is locked: terraform force-unlock <lock-id>
```

> Terraform is **idempotent** — re-running apply after a partial failure will continue from the last successful resource.

### Avoiding Race Conditions

State isolation prevents most race conditions, but these patterns help:

1. **Never run two applies on the same state file simultaneously** — they'll conflict
2. **Use CI/CD for all applies** — no concurrent manual applies
3. **Monitor for state lock errors** (even though Spaces doesn't natively lock, Git's branch protection prevents simultaneous merges)

---

## 📝 Documentation Standards

### What Must Be Documented

| Item | Where | Detail Level |
|------|-------|-------------|
| Module purpose | Module `README.md` or inline comments | High-level: what and why |
| Variable descriptions | `variables.tf` `description` fields | One sentence per variable |
| Output descriptions | `outputs.tf` `description` fields | What this output provides |
| Module call intent | `main.tf` comments | Why this module is called with these params |
| Pipeline workflow | CI/CD YAML comments | What each job does and why order matters |
| Architecture decisions | `Docs/` markdown files | Full context, decision, consequences |

### Comment Style Guide

```hcl
# ✅ Good: explains WHY (not what)
# Using remote state instead of module output to prevent
# circular dependencies between hub and spoke layers.
data "terraform_remote_state" "core_network" {
  # ...
}

# ❌ Bad: explains WHAT (obvious from code)
# This reads the core network remote state
data "terraform_remote_state" "core_network" {
  # ...
}
```

### README Standards

Every major directory should have a brief documentation comment:

```markdown
# Modules/

Reusable Terraform building blocks for DigitalOcean infrastructure.

Each module follows the standard interface:
- `main.tf` — Resource definitions
- `variables.tf` — Input contracts
- `outputs.tf` — Output contracts
```

---

## 🏃 Operational Runbooks

### Daily Operations

```bash
# Check pipeline status
# → GitHub Actions tab → Recent workflows

# Check plan output for open PRs
# → PR page → Checks tab → Terraform Plan step

# Verify infrastructure is healthy
# → DigitalOcean dashboard
```

### Weekly Operations

```bash
# Review DigitalOcean billing for unexpected costs
# → DO Control Panel → Billing

# Check for Terraform/provider updates
# → GitHub Dependabot (if enabled)

# Verify state file backups (Spaces versioning)
# → DO Spaces → Bucket → File version history
```

### Incident Response

| Incident | Detection | Response |
|----------|-----------|----------|
| Apply failure | CI job failure notification | Check logs, fix code, re-run |
| Resource accidentally deleted | User reports outage | Check state + apply to recreate |
| State file corrupted | Terraform errors | Restore from Spaces versioning |
| Security breach | DO alert / GitHub alert | Rotate tokens, audit changes |
| High costs | Billing alert | Review resources, downsize if needed |

### Environment Cleanup

To tear down a complete environment (e.g., dev at end of sprint):

```bash
# Destroy in REVERSE order of creation:

# 1. Spoke Identity (project binding)
cd Workload/Spokes/fintrack/identity
terraform destroy -var-file=../../../../Deployment/Spokes/fintrack/dev.tfvars

# 2. Spoke Data (MongoDB)
cd ../data
terraform destroy -var-file=../../../../Deployment/Spokes/fintrack/dev.tfvars

# 3. Spoke Network (droplets + firewall)
cd ../network
terraform destroy -var-file=../../../../Deployment/Spokes/fintrack/dev.tfvars

# 4. Hub Identity
cd Workload/Core/identity
terraform destroy -var-file=../../../Deployment/Core/global.tfvars

# 5. Hub Network (VPC) — last!
cd ../network
terraform destroy -var-file=../../../Deployment/Core/global.tfvars
```

> ⚠️ **Destroy order matters**! Destroying the VPC while droplets/MongoDB still reference it will leave resources **orphaned** in DigitalOcean (they still exist but can't be managed by Terraform).

---

## 📚 Related Documents

| Document | Description |
|----------|-------------|
| [README.md](../readme.md) | Project overview and quick start |
| [architecture.md](architecture.md) | Architecture deep dive |
| [ci-cd-pipeline.md](ci-cd-pipeline.md) | CI/CD workflow deep dive |
| [reference-architecture.md](reference-architecture.md) | Enterprise reference patterns |
