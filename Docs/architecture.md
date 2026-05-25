# Architecture Deep Dive — What I Built and Why 🏗️

> **If you're new to Terraform or cloud networking, start here. I'll explain everything I learned, including the mistakes, the "aha" moments, and why I made each decision.**

---

## Table of Contents

- [Hub-and-Spoke for Beginners](#-hub-and-spoke-for-beginners)
- [Layer Architecture: Why I Split Things Up](#-layer-architecture-why-i-split-things-up)
- [The State Bridge Pattern (How Layers Talk)](#-the-state-bridge-pattern-how-layers-talk)
- [Module Design: Building Blocks](#-module-design-building-blocks)
- [Configuration vs. Logic: The Deployment/ Trick](#-configuration-vs-logic-the-deployment-trick)
- [Workload Layout: The Six-File Pattern](#-workload-layout-the-six-file-pattern)
- [Provisioning Order: What Deploys When](#-provisioning-order-what-deploys-when)
- [Network Architecture](#-network-architecture)
- [Data Tier: Managed MongoDB on DO](#-data-tier-managed-mongodb-on-do)
- [Identity & Project Binding](#-identity--project-binding)
- [Security: What I Protected and How](#-security-what-i-protected-and-how)
- [Design Decisions: The "Why" Behind Everything](#-design-decisions-the-why-behind-everything)
- [Extending This (If You Want to Fork It)](#-extending-this-if-you-want-to-fork-it)

---

## 🧠 Hub-and-Spoke for Beginners

### The "Apartment Building" Analogy

I struggled to understand hub-and-spoke at first. Here's what made it click for me:

Imagine an **apartment building**:

- **The Hub** is the building itself — the lobby, the elevator, the mail room, the shared WiFi. Every apartment (spoke) needs these things, and they're managed centrally.
- **Each Spoke** is a single apartment. It has its own rooms (servers), its own furniture (databases), and its own door number (project). One apartment can't break into another apartment.
- **The connection** is the building's shared hallway network. Everyone uses it, but your door locks keep you safe.

In cloud terms:

```
                    ┌──────────────┐
                    │   THE HUB    │
                    │  (Core VPC)  │
                    │ 10.0.0.0/16  │
                    └──────┬───────┘
                           │
            ┌──────────────┼──────────────┐
            │              │              │
            ▼              ▼              ▼
     ┌──────────┐   ┌──────────┐   ┌──────────┐
     │  Spoke 1 │   │  Spoke 2 │   │  Spoke 3 │
     │ FinTrack │   │  (New)   │   │  (New)   │
     └──────────┘   └──────────┘   └──────────┘
```

### Why Not Just Put Everything in One VPC?

I tried that first. It was a mess. Here's why hub-and-spoke won:

| One Big VPC (My First Try) | Hub-and-Spoke (What I Should Have Done) |
|----------------------------|----------------------------------------|
| One state file. One bug corrupts everything. | Each piece has its own state. Disaster stays contained. |
| A typo in the database config affects the web servers. | Each layer is independent — a DB mistake stays in the data layer. |
| Plans take 2+ minutes because Terraform evaluates everything. | Plans take seconds — each layer is small. |
| Can't let a junior dev touch anything safely. | A junior can work on a spoke without risking the whole setup. |
| Adding a new app means editing the same giant config. | Adding a new app = new spoke directory. Done. |

### What the Hub Owns vs. What Spokes Own

| Component | Hub | Spoke |
|-----------|-----|-------|
| **Network** | The corporate VPC (10.0.0.0/16) | Droplets that connect to the Hub VPC |
| **Identity** | Root project workspace | App-specific project binding |
| **Data** | Global storage (placeholder for future) | Application database (MongoDB) |
| **Security** | N/A (firewalls are per-spoke) | Firewall rules for the app's droplets |

---

## 🧩 Layer Architecture: Why I Split Things Up

### My First Mistake: The Monolithic State File

When I started, I had all infrastructure in one Terraform configuration. One state file. One `main.tf` that was 400 lines long. Every `terraform plan` took forever.

Then I learned about **state isolation** — the idea that each logical unit should manage its own state. Here's what I ended up with:

```
📦 fintrack-tfstate-bucket/
│
├── core/                        ← HUB STATE FILES
│   ├── network.tfstate          │  Core Network (VPC)
│   ├── identity.tfstate         │  Core Identity (Project)
│   └── data.tfstate             │  Core Data (Storage)
│
└── spokes/                      ← SPOKE STATE FILES
    └── fintrack/
        ├── network.tfstate      │  FinTrack Compute + Firewall
        ├── data.tfstate         │  FinTrack MongoDB
        └── identity.tfstate     │  FinTrack Project Binding
```

> 📝 **Note**: I originally used `core/network/global.tfstate` as the key convention, but then switched to `core/network.tfstate` for consistency. If you're reading old code, you might see a mix — I standardized on the flat key format.

### Why 6 State Files Instead of 1?

Each state file is an **independent failure domain**. That means:

1. **Parallel safety** — I can plan/apply multiple layers at the same time (as long as they don't depend on each other)
2. **Small blast radius** — If the MongoDB state gets corrupted, the VPC and compute are still fine
3. **Fast operations** — Each state file tracks only 2-10 resources. Plans take seconds.
4. **Granular permissions** — Different people (or CI jobs) can own different state files
5. **Easy rollback** — Need to revert a change to the firewall? Just re-apply the network layer's state

### The Three Layers Per Environment

Each environment (currently just `dev` under `fintrack`) has three layers:

| Layer | What It Does | Can Be Destroyed? | Why Separate? |
|-------|-------------|-------------------|---------------|
| **Network** | Creates Droplets and Firewall rules | Yes — but database loses connectivity | Compute scales independently of storage |
| **Data** | Creates MongoDB cluster | Yes — but project loses DB reference | Database version upgrades don't affect compute |
| **Identity** | Creates DigitalOcean Project with resource bindings | Yes — purely organizational | Project structure changes don't recreate infrastructure |

This split means I can:
- Resize droplets without touching the database
- Upgrade MongoDB without recreating servers
- Reorganize projects without touching anything else

---

## 🔗 The State Bridge Pattern (How Layers Talk)

### The Problem I Needed to Solve

Layer B (Spoke Network) needs to know the Hub's VPC ID. Layer C (Spoke Data) needs to know the Spoke Network's VPC ID. But I don't want Layer C being able to modify Layer B's resources.

My first thought was to use Terraform **module outputs** — export values from one module and pass them to another. But that creates a tight dependency: both modules have to be in the same Terraform configuration.

### The Solution: Read-Only State Bridges

Each layer stores its outputs in its own state file. When another layer needs that information, it reads the state file using `data.terraform_remote_state`:

```hcl
# In Workload/Spokes/fintrack/network/data.tf
# I need the Hub's VPC ID to create droplets in the right network
data "terraform_remote_state" "core_network" {
  backend = "s3"
  config = {
    endpoint                    = "https://sgp1.digitaloceanspaces.com"
    bucket                      = var.state_bucket_name
    key                         = "core/network.tfstate"   # ← Reading Hub's state
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
```

> 💡 **Important detail**: The `skip_credentials_validation` and `skip_metadata_api_check` flags are required when using DigitalOcean Spaces instead of real AWS S3. Without them, the AWS SDK tries to run AWS-specific checks that fail against Spaces.

### The Data Flow

Think of it like a waterfall — information flows downstream, never upstream:

```
CORE (Hub)                         SPOKE (FinTrack)
────────────                      ──────────────────

Core Network ──outputs hub_vpc_id──► Spoke Network
                                       │
                                       │──outputs droplet_urns──┐
                                       │──outputs spoke_vpc_id──┤
                                                               │
                                                               ▼
                                                      Spoke Data (MongoDB)
                                                               │
                                                               │──outputs database_urn──┐
                                                                                       │
                                                                                       ▼
                                                                              Spoke Identity
                                                                              (Project Binding)
```

### What a Layer Can and Can't Do

| Operation | Hub Network | Spoke Data reading Hub's state |
|-----------|-------------|-------------------------------|
| **Create** a VPC | ✅ Yes | ❌ No (read-only) |
| **Modify** the VPC | ✅ Yes | ❌ No |
| **Read** the VPC ID | ✅ Has it | ✅ Can read it from state |
| **Delete** the VPC | ✅ Yes | ❌ No |
| **Corrupt** the VPC's state | Could affect its own state | ❌ Can't even touch it |

The Spoke can **depend** on the Hub's outputs, but it can **never** modify the Hub's resources or state. This is the core of state isolation.

---

## 📦 Module Design: Building Blocks

### The Philosophy

Modules are like LEGO bricks. Each brick does one thing well, and you combine them to build something bigger. I wanted modules that:

- Are **self-contained** — one module = one resource type
- Have **clean interfaces** — clear inputs and outputs
- Are **reusable** — use the same module for dev, staging, and production

### The Modules I Built

#### `Modules/networking` — Creates a VPC

```hcl
module "hub_vpc" {
  source     = "../../../Modules/networking"
  vpc_name   = "fintrack-corporate-vpc"
  region     = "sgp1"
  cidr_range = "10.0.0.0/16"
}
```

Simple. Three inputs, one output (`vpc_id`). Every spoke will need a VPC someday.

**What I learned**: I originally tried to make this module do more — add subnets, peering, DNS. But DigitalOcean VPCs are simpler than AWS VPCs (no subnets, no route tables). Keeping it lean means it works for every use case.

> **Note**: I also realized later that I needed a `vpc_urn` output for the project resource binding. I originally only output `vpc_id`. The research subagent caught this — I added `output "vpc_urn" { value = digitalocean_vpc.network.urn }` to fix it.

#### `Modules/droplet` — Provisions Virtual Machines

```hcl
module "fintrack_compute" {
  source        = "../../../../Modules/droplet"
  droplet_count = 2
  droplet_name  = "fintrack-dev"
  region        = "sgp1"
  size          = "s-1vcpu-1gb"
  vpc_uuid      = data.terraform_remote_state.core_network.outputs.hub_vpc_id
  tags          = ["fintrack", "dev"]
}
```

**Naming**: If `droplet_count = 1`, it creates `fintrack-dev`. If > 1, it creates `fintrack-dev-node-1`, `fintrack-dev-node-2`, etc.

**What I learned**: The `monitoring = true` flag is a tiny checkbox that gives you CPU, memory, and disk graphs in the DigitalOcean dashboard. Always enable it — debugging performance issues without metrics is like coding with your eyes closed.

#### `Modules/firewall` — Security Rules

```hcl
module "fintrack_security_barrier" {
  source        = "../../../../Modules/firewall"
  firewall_name = "fintrack-dev-firewall"
  droplet_ids   = module.fintrack_compute.droplet_ids
}
```

Opens SSH (22), HTTP (80), HTTPS (443) inbound, and all outbound traffic. Simple, but the defaults are intentionally permissive for learning. In production, you'd restrict SSH to a VPN range.

**Why separate from the droplet module?** Firewall rules change more often than compute — you might add a port or update a CIDR range without recreating the droplets.

#### `Modules/data/mongo_db` — Managed MongoDB

```hcl
module "fintrack_mongodb" {
  source                = "../../../../Modules/data/mongo_db"
  cluster_name          = "fintrack-dev-mongodb"
  environment           = "dev"
  region                = "sgp1"
  size_slug             = "db-s-1vcpu-1gb"
  node_count            = 1
  db_name               = "fintrack_dev_store"
  private_network_uuid  = data.terraform_remote_state.spoke_network.outputs.spoke_vpc_id
}
```

**Key insight**: The database is deployed to a **private network** — no public endpoint. Only resources in the same VPC can connect to it. This is the most important security decision I made.

> **Version gotcha**: I initially used `version = "7.0"` but the DigitalOcean API expects just `"7"` (the major version only). Research caught this. If you're copying this module, use `"7"` not `"7.0"`.

#### `Modules/resource_group` — DigitalOcean Project

```hcl
module "fintrack_workspace" {
  source       = "../../../../Modules/resource_group"
  project_name = "FinTrack-dev-Workspace"
  environment  = "Development"
  description  = "Environment tenant isolation container for FinTrack"
  resources    = concat(
    data.terraform_remote_state.spoke_network.outputs.droplet_urns,
    [data.terraform_remote_state.spoke_data.outputs.database_urn]
  )
}
```

A DigitalOcean Project is just a folder for organizing resources. It helps with billing (see costs by project) and management (find all related resources).

**Design issue I found**: The module currently passes resources to BOTH `digitalocean_project.resources` AND `digitalocean_project_resources`, which duplicates the binding. For a learning project it works fine, but in production you'd pick one or the other.

---

## 📄 Configuration vs. Logic: The Deployment/ Trick

### The Problem

I wanted to let someone change environment settings (like "use bigger droplets for production") without making them understand Terraform code. The solution was separating **configuration** from **logic**:

```
Deployment/
├── Core/
│   └── global.tfvars        ← Hub settings
└── Spokes/
    └── fintrack/
        └── dev.tfvars       ← FinTrack dev settings
```

### Hub Configuration (`Deployment/Core/global.tfvars`)

```hcl
region       = "sgp1"
environment  = "dev"
project_name = "fintrack-Core-Hub"
vpc_cidr     = "10.0.0.0/16"
```

### Spoke Configuration (`Deployment/Spokes/fintrack/dev.tfvars`)

```hcl
region             = "sgp1"
environment        = "dev"
app_name           = "fintrack"
state_bucket_name  = "fintrack-tfstate-bucket"
droplet_size       = "s-1vcpu-1gb"
instance_count     = 1
db_size_slug       = "db-s-1vcpu-1gb"
db_node_count      = 1
initial_database   = "fintrack_dev_store"
```

### How to Add Production

Just create a new `.tfvars` file — no code changes needed:

```hcl
# Deployment/Spokes/fintrack/prod.tfvars
droplet_size       = "s-4vcpu-8gb"
instance_count     = 3
db_size_slug       = "db-s-4vcpu-8gb"
db_node_count      = 3
initial_database   = "fintrack_prod_store"
```

> 📝 **This was a huge "aha" moment for me.** Once I realized I could have different `.tfvars` files for different environments WITHOUT duplicating Terraform code, everything clicked. The modules are the logic. The `.tfvars` are the config. Keep them separate.

---

## 📁 Workload Layout: The Six-File Pattern

Every workload directory follows this exact pattern:

| File | What It Does |
|------|-------------|
| `providers.tf` | Says "I use Terraform >= 1.5.0 and the DigitalOcean provider" |
| `backend.tf` | Says "use S3 backend" (partial — real config comes from CI) |
| `variables.tf` | Lists all input variables with types and descriptions |
| `data.tf` | Reads state from upstream layers using `terraform_remote_state` |
| `main.tf` | Calls modules to create actual infrastructure |
| `outputs.tf` | Exposes values that downstream layers need |

Once I established this pattern, navigating the repo became automatic. Every directory looks the same. No surprises.

---

## 🔀 Provisioning Order: What Deploys When

### The Dependency Chain

```
                    ┌──────────────────┐
                    │  Core Network    │  (No dependencies — deploy first)
                    │  (Hub VPC)       │
                    └────────┬─────────┘
                             │ hub_vpc_id
                             ▼
                    ┌──────────────────┐
                    │ Spoke Network    │  (Needs Core Network's VPC ID)
                    │ (Droplets + FW)  │
                    └────────┬─────────┘
                             │ spoke_vpc_id, droplet_urns
                             ▼
                    ┌──────────────────┐
                    │  Spoke Data      │  (Needs Spoke Network's VPC ID)
                    │  (MongoDB)       │
                    └────────┬─────────┘
                             │ database_urn
                             ▼
                    ┌──────────────────┐
                    │ Spoke Identity   │  (Needs URNs from Network + Data)
                    │ (Project)        │
                    └──────────────────┘
```

### What Happens If You Deploy Out of Order

| Scenario | Result |
|----------|--------|
| Spoke Network before Core Network ❌ | `terraform plan` fails — can't find Hub state |
| Spoke Data before Spoke Network ❌ | `terraform plan` fails — can't find Spoke Network state |
| Spoke Identity before Spoke Data ❌ | `terraform plan` fails — can't find Spoke Data state |
| Destroy Core Network while Spokes exist ❌ | Spoke resources lose VPC binding (orphaned resources!) |

**Rule**: Hub first. Then Network → Data → Identity. Destroy in reverse.

---

## 🌍 Network Architecture

### The Hub VPC

| Property | Value | Why |
|----------|-------|-----|
| Name | `fintrack-corporate-vpc` | Clearly identifies what this is |
| Region | `sgp1` | Singapore — closest datacenter to me |
| CIDR | `10.0.0.0/16` | 65,536 IPs — enough for many spokes |
| Resource | `digitalocean_vpc` | DigitalOcean's software-defined network |

### How Droplets Connect

All droplets reference the Hub VPC via `vpc_uuid`:

```hcl
resource "digitalocean_droplet" "vm" {
  vpc_uuid = var.vpc_uuid  # ← This connects them to the Hub's private network
}
```

This means droplets in any spoke can communicate over private IPs. The MongoDB database doesn't need a public endpoint — it talks to the app servers over the private network.

### Firewall Rules (The Defaults)

| Rule | Port | Source | Why So Permissive? |
|------|------|--------|-------------------|
| SSH Inbound | 22 | 0.0.0.0/0 | For learning — restrict in production |
| HTTP Inbound | 80 | 0.0.0.0/0 | Web traffic |
| HTTPS Inbound | 443 | 0.0.0.0/0 | Secure web traffic |
| All Outbound | TCP/UDP 1-65535 | 0.0.0.0/0 | System updates, API calls, DNS |

> ⚠️ **Learning project alert**: SSH from `0.0.0.0/0` is fine for a sandbox, but DON'T do this in production. Restrict it to your VPN IP range.

---

## 🗄️ Data Tier: Managed MongoDB on DO

DigitalOcean's managed databases handle the hard parts:
- Automated backups (turn them on!)
- Automated failover (with 3+ nodes)
- Security patching (DO does it for you)
- Monitoring (CPU, memory, disk, queries)

### Why Private Network?

The database cluster is deployed without a public endpoint:

```hcl
resource "digitalocean_database_cluster" "mongodb_cluster" {
  private_network_uuid = var.private_network_uuid  # ← Only accessible via VPC
}
```

This is the most important security measure in the entire project. The database is invisible to the internet. Only droplets inside the same VPC can reach it — and they do so over a private IP (faster and free).

### Dev vs. Production Sizing

| Environment | Node Count | Why |
|-------------|-----------|-----|
| Dev | 1 | Cheap to run ($15/mo), fine for testing |
| Production | 3 | High-availability replica set — auto-failover if a node dies |

---

## 🪪 Identity & Project Binding

### What Are DigitalOcean Projects?

Think of a Project as a **folder** in your DigitalOcean account. You can group related resources together, see their combined cost, and manage them as a unit.

### How the Identity Layer Works

The identity layer is unique — it doesn't create its own resources. Instead, it **collects URNs** (Universal Resource Names) from the network and data layers, then bundles them into a Project:

```hcl
module "fintrack_workspace" {
  resources = concat(
    data.terraform_remote_state.spoke_network.outputs.droplet_urns,   # From compute
    [data.terraform_remote_state.spoke_data.outputs.database_urn]     # From DB
  )
}
```

| URN Source | Resource Type | Example |
|------------|--------------|---------|
| `spoke_network` | Droplets | `do:droplet:123456789` |
| `spoke_data` | Database | `do:database:987654321` |

Both are combined with `concat()` and attached to the project.

### Hub Identity

The Hub identity follows the same pattern but only binds the VPC:

```hcl
module "core_global_workspace" {
  resources = [
    data.terraform_remote_state.core_network.outputs.hub_vpc_urn
  ]
}
```

> **What I learned the hard way**: The networking module needs to output `vpc_urn` for this to work. My original module only output `vpc_id`. The Core Identity layer was referencing `hub_vpc_urn` which didn't exist. This would have failed at `terraform plan` time. The research subagent caught this before I deployed.

---

## 🔒 Security: What I Protected and How

### Defense in Depth (Even for a Learning Project)

| Layer | What I Did |
|-------|-----------|
| **Network** | Private VPC — droplets use private networking |
| **Firewall** | Explicit inbound rules (only SSH, HTTP, HTTPS) |
| **Database** | Private network only — no public endpoint |
| **Secrets** | Zero secrets in code. All injected at CI runtime |
| **CI/CD** | Plan-Apply split — every change is reviewed before execution |
| **State** | State files in encrypted Spaces bucket with versioning |

### How Secrets Flow

```
GitHub Encrypted Secrets
    │
    ├── DIGITALOCEAN_TOKEN ──────────► Terraform provider auth
    ├── DO_SPACES_ACCESS_KEY ────────► Terraform backend auth
    ├── DO_SPACES_SECRET_KEY ────────► Terraform backend auth
    └── DO_SPACES_BUCKET ───────────► State file location
```

Nothing is committed to Git. Not the token, not the keys, not even the bucket name (it's in GitHub Secrets too).

---

## ✅ Design Decisions: The "Why" Behind Everything

### Why DigitalOcean Spaces Instead of Terraform Cloud?

| Factor | Spaces | Terraform Cloud |
|--------|--------|-----------------|
| Cost | Included with Spaces ($5/mo) | Free tier, paid tiers scale |
| Complexity | S3-compatible API — very simple | Another service to learn |
| Latency | Same-region (sgp1) | Global |
| State Locking | No native locking | Built-in |

**My choice**: Spaces. I was already using DigitalOcean, and S3-compatible storage is a transferable skill (works with AWS, GCS, and MinIO too). The trade-off is no native state locking, but for a single-developer learning project, that's fine.

### Why GitHub Actions?

GitHub Actions keeps CI/CD right next to the code. The reusable workflow pattern (`workflow_call`) let me define the plan/apply logic once and call it 6 times (3 plan jobs + 3 apply jobs). No copy-pasting pipeline code.

### Why MongoDB 7.0?

It's the latest stable version. I wanted to practice with something current. The DigitalOcean managed MongoDB handles backups, patching, and failover — I didn't want to manage a database server myself.

### Why `region = "us-east-1"` in the Spaces Backend?

This confused me for hours. DigitalOcean Spaces doesn't use AWS regions — it uses custom endpoints like `sgp1.digitaloceanspaces.com`. But the AWS S3 driver that Terraform uses internally insists on a `region` parameter. `us-east-1` is a dummy value that satisfies the SDK without affecting anything. The actual connection target is the `endpoint` URL.

---

## 🚀 Extending This (If You Want to Fork It)

This is a learning project, so it's designed to be extended. Here are things I'd try next:

### Add a New Spoke (e.g., "payment-service")

```text
Workload/Spokes/payment-service/
├── network/    → module "payment_compute" from droplet + firewall
├── data/       → module "payment_database" from mongo_db
└── identity/   → module "payment_workspace" from resource_group
```

Plus `Deployment/Spokes/payment-service/dev.tfvars` and new pipeline jobs.

### Add Kubernetes (DOKS)

I'd create `Modules/doks/` for DigitalOcean Kubernetes and swap out the droplet module in the network layer. The identity layer still works the same way — it just collects URNs.

### Add State Locking

DigitalOcean Spaces doesn't have native locking. For $0 (on Terraform Cloud's free tier), I could get state locking and a UI. Or I could create a DynamoDB table in AWS just for locks (cross-provider, but it works).

---

## 📚 Related Docs

| Document | What It Covers |
|----------|---------------|
| [README.md](../readme.md) | Project overview, what I learned, gotchas, getting started |
| [ci-cd-pipeline.md](ci-cd-pipeline.md) | The GitOps pipeline, Headless Init Fix, artifact flow |
| [reference-architecture.md](reference-architecture.md) | Ways to extend: multi-spoke, multi-region, cost estimates |
| [best-practices.md](best-practices.md) | Lessons I learned the hard way: state, secrets, naming |
