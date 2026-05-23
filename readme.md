# FinTrack Multi-Tier Hub-and-Spoke Infrastructure Landing Zone

![DigitalOcean](https://img.shields.io/badge/Cloud-DigitalOcean-0060FF?logo=digitalocean)
![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform)
![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=githubactions)
![License](https://img.shields.io/badge/License-MIT-green)

A production-grade **Infrastructure as Code (IaC)** repository that provisions a fully decoupled **Hub-and-Spoke** network architecture on **DigitalOcean**, automated through a **GitOps CI/CD pipeline** using **GitHub Actions** and **Terraform**.

---

## 📖 Table of Contents

- [What Is This?](#-what-is-this)
- [Architecture Overview](#-architecture-overview)
- [Repository Structure Explained](#-repository-structure-explained)
- [Key Concepts](#-key-concepts)
- [How Terraform Works Here](#-how-terraform-works-here)
- [CI/CD Pipeline](#-cicd-pipeline)
- [Getting Started](#-getting-started)
- [Prerequisites](#-prerequisites)
- [Local Development Workflow](#-local-development-workflow)
- [Security & Secrets Management](#-security--secrets-management)
- [Reference Documentation](#-reference-documentation)
- [Troubleshooting](#-troubleshooting)

---

## 🧭 What Is This?

This repository contains an **enterprise-grade cloud infrastructure landing zone** — a pre-built, reusable foundation for deploying applications on DigitalOcean safely and consistently.

Think of it as a **blueprint for a secure, multi-layered cloud environment** where:

- 🏢 The **Hub** is the corporate network backbone (VPC, central policies)
- 🏗️ The **Spokes** are individual application environments (compute, database, identity)
- 🔗 **State bridges** connect layers without creating tight dependencies
- 🤖 A **GitOps CI/CD engine** ensures every change is reviewed, planned, and applied automatically

The infrastructure runs out of the **Singapore (sgp1)** datacenter region and is designed for the **FinTrack** application — but the patterns apply to any cloud-native workload.

---

## 🏛️ Architecture Overview

### Hub-and-Spoke Model

```
                         ┌─────────────────────────────────┐
                         │         ☁️ DigitalOcean         │
                         │         Region: sgp1            │
                         └─────────────────────────────────┘
                                     │
        ┌────────────────────────────┼────────────────────────────┐
        │                            │                            │
        ▼                            ▼                            ▼
┌──────────────────┐    ┌──────────────────────────┐    ┌──────────────────┐
│   HUB (Core)     │    │    SPOKE: FinTrack        │    │   Future Spokes  │
│                  │    │                            │    │                  │
│  ┌────────────┐  │    │  ┌──────────────────────┐  │    │  ┌────────────┐  │
│  │  Network   │  │    │  │    Network Layer     │  │    │  │    ...     │  │
│  │  (VPC)     │──┼────┼──│  (Droplets + FW)     │  │    │  │            │  │
│  └────────────┘  │    │  └──────────┬───────────┘  │    │  └────────────┘  │
│                  │    │             │               │    │                  │
│  ┌────────────┐  │    │  ┌──────────▼───────────┐  │    │                  │
│  │  Identity  │  │    │  │    Data Layer         │  │    │                  │
│  │  (Project) │  │    │  │  (MongoDB Cluster)    │  │    │                  │
│  └────────────┘  │    │  └──────────┬───────────┘  │    │                  │
│                  │    │             │               │    │                  │
│  ┌────────────┐  │    │  ┌──────────▼───────────┐  │    │                  │
│  │   Data     │  │    │  │   Identity Layer      │  │    │                  │
│  │ (Storage)  │  │    │  │  (Project Binding)    │  │    │                  │
│  └────────────┘  │    │  └──────────────────────┘  │    │                  │
└──────────────────┘    └──────────────────────────┘    └──────────────────┘
```

### Data Flow Between Layers

Each layer reads outputs from the layer **above it** using Terraform's `data.terraform_remote_state`. This creates a **read-only state bridge** — information flows downstream, but no layer can accidentally modify another.

```text
Hub Network (Core)
    │
    │  reads hub_vpc_id via terraform_remote_state
    ▼
Spoke Network (FinTrack Compute + Firewall)
    │
    │  reads spoke_vpc_id via terraform_remote_state
    ▼
Spoke Data (FinTrack MongoDB)
    │
    │  reads droplet_urns + database_urn via terraform_remote_state
    ▼
Spoke Identity (FinTrack Project Workspace)
```

> 🔑 **Key design principle**: Each layer has its own **isolated Terraform state file**. A mistake in the data layer can never corrupt the network layer.

---

## 📂 Repository Structure Explained

```
.
├── .github/workflows/           # CI/CD pipeline definitions (GitHub Actions)
│   ├── fintrack-pipeline.yml    # Main orchestrator — triggers plans & applies
│   ├── terraform-plan.yml       # Reusable plan workflow (called by pipeline)
│   └── terraform-apply.yml      # Reusable apply workflow (called by pipeline)
│
├── Deployment/                   # Central configuration parameters (.tfvars)
│   ├── Core/
│   │   └── global.tfvars        # Hub-level variables (region, VPC CIDR, project name)
│   └── Spokes/
│       └── fintrack/
│           └── dev.tfvars       # Spoke-level variables (instance count, DB settings)
│
├── Modules/                      # Reusable Terraform building blocks
│   ├── droplet/                  # Compute node (virtual machine) generator
│   ├── firewall/                 # Security group rules (inbound/outbound)
│   ├── networking/               # VPC (Virtual Private Cloud) network
│   ├── data/mongo_db/            # Managed MongoDB 7.0 database cluster
│   └── resource_group/           # DigitalOcean Project workspace container
│
├── Workload/                     # Declarative infrastructure layouts
│   ├── Core/                     # Hub: global shared services
│   │   ├── network/              #   Corporate VPC backbone
│   │   ├── identity/             #   Root project workspace
│   │   └── data/                 #   Global storage (future use)
│   └── Spokes/                   # Application environments
│       └── fintrack/
│           ├── network/          #   Compute droplets + firewall rules
│           ├── data/             #   MongoDB database cluster
│           └── identity/         #   App project workspace bindings
│
├── Docs/                         # 📚 Documentation (this directory!)
│   ├── architecture.md           # Deep dive into architecture patterns
│   ├── ci-cd-pipeline.md         # CI/CD pipeline explanation
│   ├── reference-architecture.md # Enterprise reference patterns
│   └── best-practices.md         # Best practices enforced in this repo
│
└── readme.md                     # ← You are here
```

---

## 🎯 Key Concepts

### 1. Hub-and-Spoke Architecture

A networking model where a **central Hub** (core VPC, identity) provides shared services to isolated **Spoke** environments. Benefits:

| Benefit | Explanation |
|---------|------------|
| **Isolation** | Each spoke is independent — crashes or misconfigurations stay contained |
| **Reusability** | Add new application spokes without touching the hub |
| **Central Governance** | Policy, networking, and security are defined once in the hub |
| **Blast Radius Control** | A bad deployment affects only its spoke, not the entire organization |

### 2. Remote State Data Bridge

Terraform state files contain the current status of all infrastructure. In this repo:

- Each layer has **its own state file** stored in DigitalOcean Spaces (S3-compatible)
- Layers read each other's state using `data.terraform_remote_state`
- This creates a **read-only data flow** — Layer B can **see** Layer A's outputs but cannot **change** them

```hcl
# Example from Workload/Spokes/fintrack/network/data.tf
data "terraform_remote_state" "core_network" {
  backend = "s3"
  config = {
    endpoint = "sgp1.digitaloceanspaces.com"
    bucket   = var.state_bucket_name
    key      = "core/network/global.tfstate"  # ← Points to Hub's state
    region   = "us-east-1"
  }
}

# Then used in main.tf:
vpc_uuid = data.terraform_remote_state.core_network.outputs.hub_vpc_id
```

### 3. Modular Design

All reusable infrastructure patterns are extracted into **Modules/**:

| Module | What It Creates | Why Separate? |
|--------|----------------|---------------|
| `networking` | A VPC network | Share across any spoke that needs a network |
| `droplet` | One or more virtual machines | Consistent compute sizing, naming, tagging |
| `firewall` | Security rules for droplets | Standardized port policies |
| `mongo_db` | Managed MongoDB 7.0 cluster | Consistent database deployments |
| `resource_group` | A DigitalOcean Project | Organize resources under logical containers |

### 4. Separation of Concerns

The repository separates infrastructure into **three distinct planes**:

- **Configuration** (Deployment/) — `.tfvars` files with environment-specific values
- **Logic** (Modules/) — Reusable Terraform code that creates resources
- **Execution** (Workload/) — Concrete instantiations that wire modules to configurations

This means you can change a value in `dev.tfvars` without touching any Terraform logic, and vice versa.

### 5. GitOps Deployment Model

**GitOps** means **Git is the single source of truth**:

1. Infrastructure changes are proposed via **Pull Requests**
2. The CI pipeline runs `terraform plan` and uploads the plan as an artifact
3. Team members review the plan output in the PR
4. Merging to `main` triggers `terraform apply` using the exact same plan
5. **No manual `terraform apply` ever** — everything goes through Git

---

## ⚙️ How Terraform Works Here

### State Management

Terraform state (the record of what infrastructure exists) is stored in **DigitalOcean Spaces** (an S3-compatible object storage). Each layer gets its own state file:

```text
fintrack-tfstate-bucket/
├── core/
│   ├── network/global.tfstate    ← Hub VPC state
│   ├── identity/global.tfstate   ← Hub project state
│   └── data/global.tfstate       ← Hub storage state
└── spokes/
    └── fintrack/
        ├── network.tfstate       ← FinTrack compute state
        ├── data.tfstate          ← FinTrack MongoDB state
        └── identity.tfstate      ← FinTrack project state
```

### Provider Configuration

Each workload directory has:
- **`providers.tf`** — Declares Terraform version, provider source (`digitalocean/digitalocean ~> 2.39.0`)
- **`backend.tf`** — Partial backend config (`backend "s3" {}`). Full config injected at CI runtime
- **`variables.tf`** — Input variables for this layer
- **`data.tf`** — Remote state data sources (reads from upstream layers)
- **`main.tf`** — Module calls that create resources
- **`outputs.tf`** — Values exposed to downstream layers

### The Headless Initialization Fix

When using partial S3 backend configuration, Terraform can hang in CI asking for an AWS region interactively. This repo bypasses that by injecting `region=us-east-1` at init time:

```bash
terraform init \
  -backend-config="bucket=${{ secrets.DO_SPACES_BUCKET }}" \
  -backend-config="endpoint=sgp1.digitaloceanspaces.com" \
  -backend-config="key=${{ inputs.state_key }}" \
  -backend-config="access_key=${{ secrets.DO_SPACES_ACCESS_KEY }}" \
  -backend-config="secret_key=${{ secrets.DO_SPACES_SECRET_KEY }}" \
  -backend-config="region=us-east-1"   # ← Critical fix!
```

> DigitalOcean Spaces uses regional endpoints (like `sgp1.digitaloceanspaces.com`), not AWS geographic regions, but the S3 driver still needs a region string to pass its validation.

---

## 🔄 CI/CD Pipeline

The pipeline follows a strict **Plan-Apply Split** pattern:

```
Pull Request (feature branch)
    │
    ├── terraform fmt -check        # Code formatting validation
    ├── terraform init              # Initialize with backend config
    ├── terraform validate          # Syntax and logic validation
    └── terraform plan -out=tfplan  # Generate execution plan binary
        └── Upload tfplan as artifact
    │
    Review plan in PR comments
    │
Merge to main
    │
    ├── terraform init              # Same init process
    ├── Download tfplan artifact    # Use the EXACT same plan binary
    └── terraform apply tfplan      # Execute
```

### Sequential Execution Order

Jobs run in strict sequence because of inter-layer dependencies:

```text
[PR Phase]
plan-network → plan-data → plan-identity

[Merge Phase]
apply-network → apply-data → apply-identity
```

> ⚠️ **Critical**: The data layer waits for the network layer because MongoDB needs the VPC ID. Identity waits for data because it needs URNs from both compute and database.

*For full pipeline details, see [Docs/ci-cd-pipeline.md](Docs/ci-cd-pipeline.md)*

---

## 🚀 Getting Started

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | >= 1.5.0 | Infrastructure provisioning |
| [DigitalOcean Account](https://cloud.digitalocean.com/) | — | Cloud provider |
| [DigitalOcean Spaces Bucket](https://www.digitalocean.com/products/spaces) | — | Terraform state storage |
| [GitHub Account](https://github.com/) | — | Source control + CI/CD |
| [Doctl CLI](https://docs.digitalocean.com/reference/doctl/) (optional) | — | Local DigitalOcean management |

### Required GitHub Secrets

Set these in your GitHub repository → Settings → Secrets and variables → Actions:

| Secret | Description |
|--------|-------------|
| `DIGITALOCEAN_TOKEN` | DigitalOcean personal access token with read/write scope |
| `DO_SPACES_ACCESS_KEY` | Spaces access key (from DigitalOcean API → Spaces) |
| `DO_SPACES_SECRET_KEY` | Spaces secret key |
| `DO_SPACES_BUCKET` | Name of your Spaces bucket (e.g., `fintrack-tfstate-bucket`) |

### One-Time Hub Bootstrap

The Hub infrastructure (VPC, identity) must be deployed manually first since there's no upstream state to depend on:

```bash
# Deploy Core Network
cd Workload/Core/network
terraform init -backend-config="bucket=<your-bucket>" \
               -backend-config="endpoint=sgp1.digitaloceanspaces.com" \
               -backend-config="key=core/network/global.tfstate" \
               -backend-config="access_key=<your-access-key>" \
               -backend-config="secret_key=<your-secret-key>" \
               -backend-config="region=us-east-1"
terraform apply -var-file=../../../Deployment/Core/global.tfvars

# Deploy Core Identity
cd ../identity
# ... same init pattern with key=core/identity/global.tfstate
terraform apply -var-file=../../../Deployment/Core/global.tfvars
```

---

## 💻 Local Development Workflow

```bash
# 1. Create a feature branch
git checkout -b feature/add-autoscaling-group

# 2. Make your changes (edit modules, variables, etc.)

# 3. Format all Terraform files
terraform fmt -recursive

# 4. Validate syntax locally
cd Workload/Spokes/fintrack/network
terraform init -backend=false
terraform validate

# 5. Commit and push
git add .
git commit -m "feat: add autoscaling configuration"
git push origin feature/add-autoscaling-group

# 6. Open a Pull Request → CI runs terraform plan
# 7. Review the plan output in PR
# 8. Merge to main → CI runs terraform apply
```

---

## 🔒 Security & Secrets Management

### What's NEVER in the Codebase

| Item | Where It Lives |
|------|---------------|
| DigitalOcean API tokens | GitHub Encrypted Secrets |
| Spaces access/secret keys | GitHub Encrypted Secrets |
| Spaces bucket name | GitHub Encrypted Secrets |
| Database connection strings | Output of `terraform apply` |
| SSH private keys | Not managed here |

### Firewall Rules

The standardized firewall module opens:

| Direction | Protocol | Port(s) | Source | Purpose |
|-----------|----------|---------|--------|---------|
| Inbound | TCP | 22 | 0.0.0.0/0 | SSH access (narrow in production) |
| Inbound | TCP | 80 | 0.0.0.0/0 | HTTP web traffic |
| Inbound | TCP | 443 | 0.0.0.0/0 | HTTPS web traffic |
| Outbound | TCP | 1-65535 | 0.0.0.0/0 | System updates, API calls |
| Outbound | UDP | 1-65535 | 0.0.0.0/0 | DNS resolution |

---

## 📚 Reference Documentation

| Document | What It Covers |
|----------|---------------|
| [Docs/architecture.md](Docs/architecture.md) | Deep dive: Hub-and-Spoke, state bridges, layer isolation, and module design |
| [Docs/ci-cd-pipeline.md](Docs/ci-cd-pipeline.md) | Full CI/CD walkthrough: workflows, jobs, plan binaries, artifact flow |
| [Docs/reference-architecture.md](Docs/reference-architecture.md) | Enterprise patterns: multi-spoke, multi-region, production hardening |
| [Docs/best-practices.md](Docs/best-practices.md) | Engineering standards: state isolation, secret management, GitOps, module design |

---

## 🔧 Troubleshooting

### `terraform init` Hangs / Asks for Region

**Cause**: Partial `backend "s3" {}` config without a region. DigitalOcean Spaces uses custom endpoints, but the S3 driver needs a region string.

**Fix**: Always pass `-backend-config="region=us-east-1"` alongside your Spaces configuration.

### State Lock Errors

If `terraform apply` fails midway, the state file may be locked:

```bash
# Force unlock (use cautiously!)
terraform force-unlock <lock-id>
```

### Plan-Apply Binary Mismatch

If you see "plan file was created by a different process", the plan artifact was generated with different code than what's being applied. Ensure:
1. The PR branch is up to date with `main`
2. No force-pushes happened between plan and merge

### Permission Denied / 401

Check your GitHub Secrets are set correctly and the DigitalOcean token has the right scopes (read + write).

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes following the existing patterns
4. Run `terraform fmt -recursive` before committing
5. Open a Pull Request with a clear description of the change

---

## 📄 License

MIT — See [LICENSE](LICENSE) file for details.
