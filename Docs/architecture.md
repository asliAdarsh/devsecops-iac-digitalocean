# Architecture Deep Dive

> **Audience**: Infrastructure engineers, DevOps practitioners, and solutions architects who want to understand every design decision in this repository.

---

## Table of Contents

- [Foundational Philosophy](#-foundational-philosophy)
- [Hub-and-Spoke Network Topology](#-hub-and-spoke-network-topology)
- [Layer Architecture & State Isolation](#-layer-architecture--state-isolation)
- [Remote State Data Bridge Pattern](#-remote-state-data-bridge-pattern)
- [Module Design & Abstraction](#-module-design--abstraction)
- [Configuration Matrix (Deployment/)](#-configuration-matrix-deployment)
- [Workload Layout Patterns](#-workload-layout-patterns)
- [Provisioning Order & Dependency Graph](#-provisioning-order--dependency-graph)
- [Network Architecture](#-network-architecture)
- [Data Tier Architecture](#-data-tier-architecture)
- [Identity & Project Binding](#-identity--project-binding)
- [Security Architecture](#-security-architecture)
- [Design Decisions Explained](#-design-decisions-explained)
- [Extending the Architecture](#-extending-the-architecture)

---

## 🧠 Foundational Philosophy

This architecture is built on three core principles:

### 1. Zero-Dependency Coupling
Each infrastructure layer can be created, destroyed, or modified **without cascading effects** on other layers. Layer B reads Layer A's outputs via a **read-only data bridge** — it never writes to Layer A's state or depends on Layer A's Terraform code being present.

### 2. Blast Radius Containment
If a misconfiguration occurs in the database layer, it cannot corrupt the network layer. If a teardown happens in a spoke environment, the hub remains untouched. Each Terraform state file represents an **independent failure domain**.

### 3. Configuration over Code
Environment-specific values (region, instance size, database name) live in `.tfvars` files under `Deployment/`, **never** in the Terraform logic. This means:
- A non-engineer can change environment settings without understanding Terraform
- The same module code deploys to dev, staging, and production
- Code reviews focus on logic, not on values

---

## 🏗️ Hub-and-Spoke Network Topology

### What Is Hub-and-Spoke?

Hub-and-Spoke is a network architecture where a **central Hub** provides shared services (networking, identity, security) to multiple isolated **Spoke** environments.

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

### Why Hub-and-Spoke Instead of Flat Networking?

| Aspect | Flat Network | Hub-and-Spoke |
|--------|-------------|---------------|
| **Isolation** | All resources share one VPC | Each spoke has logical separation |
| **Blast Radius** | One bad config takes everything down | Damage stays in one spoke |
| **Scalability** | VPC limits become hard ceilings | Add unlimited spokes |
| **Governance** | Hard to enforce per-team policies | Central hub enforces policy once |
| **State Management** | One giant state file (slow, risky) | Small, independent state files |

### Hub Responsibilities

The Hub in this repo provides:

1. **Corporate VPC Backbone** (`10.0.0.0/16` in `sgp1`)
   - The fundamental private network that all resources can connect through
   - Defines the IP address space for the entire organization

2. **Root Identity Workspace**
   - A DigitalOcean Project that groups all hub resources
   - Sets the organizational naming convention

3. **Shared Data Storage** (placeholder)
   - Future: centralized artifact storage, logs, backups

### Spoke Responsibilities

Each Spoke (currently just `fintrack`) contains:

1. **Application Compute** — Droplets (VMs) running the app
2. **Application Database** — Managed MongoDB cluster
3. **Application Identity** — Project workspace binding resources

---

## 🧩 Layer Architecture & State Isolation

### The State File Map

Every layer gets its **own Terraform state file**, stored in DigitalOcean Spaces:

```
📦 fintrack-tfstate-bucket/
│
├── core/                        ← HUB STATE FILES
│   ├── network/global.tfstate   │  Core Network (VPC)
│   ├── identity/global.tfstate  │  Core Identity (Project)
│   └── data/global.tfstate      │  Core Data (Storage)
│
└── spokes/                      ← SPOKE STATE FILES
    └── fintrack/
        ├── network.tfstate      │  FinTrack Compute + Firewall
        ├── data.tfstate         │  FinTrack MongoDB
        └── identity.tfstate     │  FinTrack Project Binding
```

### Why Is State Isolation Important?

1. **Parallel Execution** — Multiple layers can be planned/applied simultaneously
2. **Reduced Blast Radius** — A corrupted state file only affects its layer
3. **Smaller Plan Times** — Each plan only evaluates ~10-50 resources instead of 500+
4. **Granular Access Control** — Different teams can own different state files
5. **Easier Rollbacks** — Roll back a single layer without affecting others

---

## 🔗 Remote State Data Bridge Pattern

### What Is a State Bridge?

A **state bridge** is a Terraform configuration that reads outputs from another layer's state file using `data.terraform_remote_state`. It enables **read-only sharing** of infrastructure metadata between layers.

### How It Works

```
┌────────────────────────────────────────────────────────┐
│                    Hub Network Layer                    │
│                                                        │
│  output "hub_vpc_id" {                                 │
│    value = digitalocean_vpc.network.id                  │
│  }                                                     │
│                                                        │
│  State stored at: core/network/global.tfstate           │
└────────────────────┬───────────────────────────────────┘
                     │
                     │  "Hey, can I read your state?"
                     ▼
┌────────────────────────────────────────────────────────┐
│               Spoke Network Layer                       │
│                                                        │
│  data "terraform_remote_state" "core_network" {         │
│    backend = "s3"                                       │
│    config = {                                           │
│      key = "core/network/global.tfstate"               │
│    }                                                    │
│  }                                                     │
│                                                        │
│  # Uses the hub's VPC ID:                              │
│  vpc_uuid = data.xxx.outputs.hub_vpc_id                 │
└────────────────────────────────────────────────────────┘
```

### Data Flow Diagram

```text
  CORE (Hub)                         SPOKE (FinTrack)
  ────────────                      ──────────────────

  ┌────────────────┐
  │ Core Network   │──outputs hub_vpc_id────────────────┐
  │ (VPC)          │                                    │
  └────────────────┘                                    ▼
                                              ┌────────────────┐
                                              │ Spoke Network   │
                                              │ (Droplets + FW) │──outputs spoke_vpc_id, droplet_urns──┐
                                              └────────────────┘                                       │
                                                                                                        ▼
                                                                                               ┌────────────────┐
                                                                                               │ Spoke Data      │
                                                                                               │ (MongoDB)       │──outputs database_urn──┐
                                                                                               └────────────────┘                       │
                                                                                                                                        ▼
                                                                                                                               ┌────────────────┐
                                                                                                                               │ Spoke Identity  │
                                                                                                                               │ (Project)       │
                                                                                                                               └────────────────┘
```

### Implementation Details

Each downstream layer has a `data.tf` file that reads the upstream state:

```hcl
# Workload/Spokes/fintrack/network/data.tf
data "terraform_remote_state" "core_network" {
  backend = "s3"
  config = {
    endpoint                    = "sgp1.digitaloceanspaces.com"
    bucket                      = var.state_bucket_name
    key                         = "core/network/global.tfstate"   # ← Hub state
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
  }
}
```

Note the `skip_credentials_validation` and `skip_metadata_api_check` flags — these are essential when using **DigitalOcean Spaces** (an S3-compatible API) instead of real AWS S3. They tell the AWS SDK not to run checks that only work against actual AWS endpoints.

### Writing vs. Reading

| Operation | Layer A (Hub) | Layer B (Spoke) |
|-----------|---------------|-----------------|
| **Write** | `terraform apply` to create VPC | ❌ Cannot modify Hub's VPC |
| **Read**  | — | `data.terraform_remote_state` reads VPC ID |
| **Delete** | Can destroy its own VPC | ❌ Cannot destroy Hub's resources |

Layer B can **depend** on Layer A's outputs, but it can **never** modify Layer A's resources or state. This is the core of **state isolation**.

---

## 📦 Module Design & Abstraction

### Philosophy

Modules are designed as **atomic building blocks** that do one thing well. They abstract away DigitalOcean resource definitions behind clean, documented variables.

### Module Catalog

#### `Modules/networking`

Creates a DigitalOcean VPC (Virtual Private Cloud).

```hcl
module "hub_vpc" {
  source     = "../../../Modules/networking"
  vpc_name   = "fintrack-corporate-vpc"
  region     = "sgp1"
  cidr_range = "10.0.0.0/16"
}
```

- **Inputs**: `vpc_name`, `region`, `cidr_range`
- **Output**: `vpc_id` — the unique identifier needed by other resources
- **Why separate?** Every spoke needs a VPC, and the VPC is the foundation of networking

#### `Modules/droplet`

Provisions one or more compute droplets (virtual machines).

```hcl
module "fintrack_compute" {
  source        = "../../../../Modules/droplet"
  droplet_count = 2                      # Creates 2 VMs
  droplet_name  = "fintrack-dev"
  region        = "sgp1"
  size          = "s-1vcpu-1gb"          # 1 vCPU, 1GB RAM
  vpc_uuid      = data.xxx.outputs.hub_vpc_id  # Bind to Hub VPC
  tags          = ["fintrack", "dev"]
}
```

- **Naming convention**: Single droplet → `fintrack-dev`. Multiple droplets → `fintrack-dev-node-1`, `fintrack-dev-node-2`
- **Built-in monitoring**: `monitoring = true` enables DigitalOcean metrics
- **Outputs**: `droplet_ids` (for firewall attachment), `droplet_urns` (for project binding)

#### `Modules/firewall`

Creates a standardized security perimeter around compute droplets.

```hcl
module "fintrack_security_barrier" {
  source        = "../../../../Modules/firewall"
  firewall_name = "fintrack-dev-firewall"
  droplet_ids   = module.fintrack_compute.droplet_ids  ← Links to local compute
}
```

- **Inbound rules**: SSH (22), HTTP (80), HTTPS (443) from anywhere
- **Outbound rules**: All TCP/UDP traffic allowed (for updates, API calls)
- **Why separate?** Firewall rules can be independently updated without recreating droplets

#### `Modules/data/mongo_db`

Provisions a managed MongoDB 7.0 cluster inside a private network.

```hcl
module "fintrack_mongodb" {
  source                = "../../../../Modules/data/mongo_db"
  cluster_name          = "fintrack-dev-mongodb"
  environment           = "dev"
  region                = "sgp1"
  size_slug             = "db-s-1vcpu-1gb"
  node_count            = 1
  db_name               = "fintrack_dev_store"
  private_network_uuid  = data.xxx.outputs.spoke_vpc_id  ← Bind to Spoke's VPC
}
```

- **Engine**: MongoDB 7.0 (the latest stable at design time)
- **Network isolation**: Deployed to the private VPC (no public endpoint)
- **Outputs**: `database_cluster_id`, `database_urn`

#### `Modules/resource_group`

Creates a DigitalOcean Project — a logical container for organizing resources.

```hcl
module "fintrack_workspace" {
  source       = "../../../../Modules/resource_group"
  project_name = "FinTrack-dev-Workspace"
  environment  = "Development"
  description  = "Environment tenant isolation container for FinTrack"
  resources    = concat(
    data.xxx.outputs.droplet_urns,     ← From Spoke Network
    [data.xxx.outputs.database_urn]    ← From Spoke Data
  )
}
```

- Optional `resources` parameter binds existing resources to the project
- Uses `concat()` to merge URN lists from multiple sources

### Module Composition Pattern

Modules are **composed** inside workload directories, not customized with complex variables:

```
Workload/Spokes/fintrack/network/main.tf
├── module "fintrack_compute"       (from Modules/droplet)
└── module "fintrack_security_barrier" (from Modules/firewall)

Workload/Spokes/fintrack/data/main.tf
└── module "fintrack_mongodb"       (from Modules/data/mongo_db)

Workload/Spokes/fintrack/identity/main.tf
└── module "fintrack_workspace"     (from Modules/resource_group)
```

Each `main.tf` is a **recipe** that assembles modules and wires their inputs/outputs.

---

## 📄 Configuration Matrix (Deployment/)

### Why a Separate Deployment Directory?

Instead of scattering variable files across workload directories, all environment configuration is centralized:

```
Deployment/
├── Core/
│   └── global.tfvars        ← Hub configuration (all environments share this)
└── Spokes/
    └── fintrack/
        └── dev.tfvars       ← FinTrack dev configuration
```

### Hub Configuration (`Deployment/Core/global.tfvars`)

```hcl
region      = "sgp1"
environment = "dev"
project_name = "fintrack-Core-Hub"
vpc_cidr    = "10.0.0.0/16"
```

- `vpc_cidr = "10.0.0.0/16"` provides 65,536 IP addresses — enough for many spokes
- `project_name` is used to name the DigitalOcean Project workspace

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

- `state_bucket_name` is referenced by `data.tf` files to find the remote state
- `droplet_size` and `db_size_slug` are separate — compute and data scale independently
- `app_name` becomes a tag on all resources for identification

### Adding a New Environment (e.g., Production)

Create `Deployment/Spokes/fintrack/prod.tfvars`:

```hcl
region             = "sgp1"
environment        = "prod"
app_name           = "fintrack"
state_bucket_name  = "fintrack-tfstate-bucket-prod"
droplet_size       = "s-2vcpu-4gb"       # Larger instances
instance_count     = 3                    # High availability
db_size_slug       = "db-s-2vcpu-4gb"
db_node_count      = 3                    # MongoDB replica set
initial_database   = "fintrack_prod_store"
```

> **No code changes needed** — just a new `.tfvars` file and the corresponding CI workflow trigger.

---

## 🌐 Workload Layout Patterns

### Why Three Layers Per Environment?

Each spoke has exactly **three** workload directories:

```
Workload/Spokes/fintrack/
├── network/     # Step 1: Compute + Firewall
├── data/        # Step 2: Database (depends on network)
└── identity/    # Step 3: Project binding (depends on network + data)
```

This 3-layer split ensures:

| Layer | Solo Responsibility | Can Be Destroyed? |
|-------|-------------------|-------------------|
| **Network** | Compute nodes, firewall rules, state bridge to Hub | Yes — but data loses connectivity |
| **Data** | MongoDB cluster, private network binding | Yes — but identity loses DB reference |
| **Identity** | Project workspace, resource URN binding | Yes — purely organizational |

### What's in Each Workload Directory?

Every workload directory follows a **consistent file structure**:

| File | Purpose | Example Content |
|------|---------|----------------|
| `providers.tf` | Terraform version & provider | `required_version = ">= 1.5.0"`, `digitalocean ~> 2.39` |
| `backend.tf` | State storage config | `backend "s3" {}` (partial — completed at init) |
| `variables.tf` | Input variables | `variable "region" { type = string }` |
| `data.tf` | Remote state reads | `data "terraform_remote_state" "..."` |
| `main.tf` | Module calls | `module "fintrack_compute" { source = "..." }` |
| `outputs.tf` | Exposed values | `output "droplet_urns" { value = module.xxx.xxx }` |

This **six-file pattern** is consistent across all 6 workload directories, making the repository predictable and easy to navigate.

---

## 🔀 Provisioning Order & Dependency Graph

### Directed Acyclic Graph (DAG)

The provisioning order forms a **DAG** — a one-way dependency chain where information flows downstream:

```
                    ┌──────────────────┐
                    │  Core Network    │  (No dependencies)
                    │  (Hub VPC)       │
                    └────────┬─────────┘
                             │ hub_vpc_id
                             ▼
                    ┌──────────────────┐
                    │ Spoke Network    │  (Depends on Core Network)
                    │ (Droplets + FW)  │
                    └────────┬─────────┘
                             │ spoke_vpc_id, droplet_urns
                             ▼
                    ┌──────────────────┐
                    │  Spoke Data      │  (Depends on Spoke Network)
                    │  (MongoDB)       │
                    └────────┬─────────┘
                             │ database_urn
                             ▼
                    ┌──────────────────┐
                    │ Spoke Identity   │  (Depends on Spoke Network + Data)
                    │ (Project)        │
                    └──────────────────┘
```

### What Happens If You Deploy Out of Order?

| Scenario | Result |
|----------|--------|
| Deploy Spoke Network before Core Network ❌ | `terraform plan` fails — can't read core state |
| Deploy Spoke Data before Spoke Network ❌ | `terraform plan` fails — can't read spoke network state |
| Deploy Spoke Identity before Spoke Data ❌ | `terraform plan` fails — can't read spoke data state |
| Destroy Core Network while Spokes exist ❌ | Spoke resources lose VPC binding (dangerous!) |

> **Rule**: Hub first. Network → Data → Identity within each spoke. Destroy in reverse order.

---

## 🌍 Network Architecture

### Hub VPC

The Hub VPC (`10.0.0.0/16`) is the **foundation of all networking**:

| Property | Value | Why |
|----------|-------|-----|
| Name | `fintrack-corporate-vpc` | Clear organizational naming |
| Region | `sgp1` | Singapore datacenter |
| CIDR | `10.0.0.0/16` | 65,536 IPs — room for many spokes |
| Resource | `digitalocean_vpc` | Software-defined network |

### Spoke Compute (Droplets)

Each spoke deploys droplets that **bind to the Hub VPC** via `vpc_uuid`:

```
Droplet (10.100.x.x)
  ├── vpc_uuid = hub_vpc_id   ← Attached to Hub's private network
  ├── image = ubuntu-24-04-lts
  ├── monitoring = true
  └── tags = ["fintrack", "dev"]
```

This means all droplets across all spokes that share the same VPC can communicate over private IPs — the database doesn't need a public endpoint.

### Firewall Rules

The firewall attaches to droplets and defines **default security boundaries**:

| Rule | Port | Purpose | Recommendation |
|------|------|---------|---------------|
| SSH Inbound | 22 | Administrative access | Narrow to VPN/corporate IP range |
| HTTP Inbound | 80 | Web traffic (redirect to HTTPS) | Keep for load balancers |
| HTTPS Inbound | 443 | Secure web traffic | Essential for production |
| All Outbound | TCP/UDP 1-65535 | System updates | Can be narrowed |

> **Production hardening**: Replace `0.0.0.0/0` inbound sources with specific IP ranges or a Cloudflare/WAF IP set.

---

## 🗄️ Data Tier Architecture

### Managed MongoDB on DigitalOcean

DigitalOcean's managed databases handle:
- Automated backups
- Automated failover (in multi-node mode)
- Regular security patching
- Metrics and monitoring

### Private Network Isolation

The database is deployed **without a public endpoint**:

```hcl
resource "digitalocean_database_cluster" "mongodb_cluster" {
  private_network_uuid = var.private_network_uuid  # ← Only accessible via VPC
  # No public access configured
}
```

This means:
- Only resources inside the same VPC can connect
- The database is not exposed to the internet
- Connection happens over private IP (faster, more secure)

### Multi-Node for Production

| Environment | Node Count | Sizing | Purpose |
|-------------|-----------|--------|---------|
| Dev | 1 | `db-s-1vcpu-1gb` | Cost-effective testing |
| Production | 3 | `db-s-2vcpu-4gb` | High-availability replica set |

> In production (3 nodes), MongoDB automatically elects a primary and handles failover if a node goes down.

---

## 🪪 Identity & Project Binding

### DigitalOcean Projects

DigitalOcean Projects are **organizational containers** that group resources:
- **Billing**: See costs grouped by project
- **Management**: View and manage related resources together
- **Permissions**: Team members can have project-scoped access

### How Resources Get Bound

The identity layer is special — it **collects URNs from upstream layers** and binds them to a project:

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

Both are combined into a single list and attached to the new project.

### Hub Identity Pattern

The Hub identity follows the same pattern but reads only from the Core Network:

```hcl
module "core_global_workspace" {
  resources = [
    data.terraform_remote_state.core_network.outputs.hub_vpc_urn
  ]
}
```

---

## 🔒 Security Architecture

### Defense in Depth

| Layer | Security Mechanism |
|-------|-------------------|
| **Network** | Private VPC (no public droplet IPs by default) |
| **Firewall** | Explicit inbound/outbound rules (default-deny inbound, allow-all outbound) |
| **Database** | Private network only — no public endpoint |
| **Secrets** | Zero secrets in code — all injected at CI runtime |
| **CI/CD** | Plan-Apply split ensures every change is reviewed |
| **State** | State files in encrypted Spaces bucket |

### Secret Flow

```
GitHub Encrypted Secrets
    │
    ├── DIGITALOCEAN_TOKEN ──────────► Terraform (DO provider auth)
    ├── DO_SPACES_ACCESS_KEY ────────► Terraform (Spaces backend auth)
    ├── DO_SPACES_SECRET_KEY ────────► Terraform (Spaces backend auth)
    └── DO_SPACES_BUCKET ───────────► Terraform (state location)
```

These are **never written** to any file in the repository. They don't appear in `.tfvars`, `variables.tf`, or any committed config.

---

## ✅ Design Decisions Explained

### Why DigitalOcean Spaces Instead of Terraform Cloud?

| Factor | DigitalOcean Spaces | Terraform Cloud |
|--------|-------------------|-----------------|
| Cost | Included with Spaces ($5/mo) | Free tier available, paid tiers scale |
| Simplicity | S3-compatible API | Additional service to manage |
| Latency | Same-region (sgp1) | Global |
| Locking | No native locking | Built-in state locking |

**Chosen**: Spaces because the project already uses DigitalOcean, and the S3-compatible API is proven. The trade-off is no native state locking.

### Why GitHub Actions Instead of GitLab CI / CircleCI?

GitHub Actions keeps the CI/CD system **co-located with the code** on GitHub. The reusable workflow pattern (`workflow_call`) enables DRY (Don't Repeat Yourself) pipeline code.

### Why MongoDB 7.0?

MongoDB 7.0 is the latest stable major version at implementation time, offering:
- Better performance and memory management
- Improved change streams (for real-time app features)
- Extended JSON schema validation
- 5+ years of vendor support

### Why `region = "us-east-1"` in Spaces Backend?

DigitalOcean Spaces is S3-compatible but uses its own endpoint format (`sgp1.digitaloceanspaces.com`). The AWS S3 SDK requires a `region` parameter to validate its configuration. Since Spaces doesn't use AWS regions, `us-east-1` is a **safe dummy value** that satisfies the SDK without affecting functionality.

---

## 🚀 Extending the Architecture

### Add a New Spoke (e.g., "payment-service")

```text
Workload/Spokes/payment-service/
├── network/
│   ├── main.tf      → module "payment_compute" (from droplet)
│   └── data.tf      → reads core/network state (hub_vpc_id)
├── data/
│   ├── main.tf      → module "payment_database" (from mongo_db)
│   └── data.tf      → reads spoke_network state (spoke_vpc_id)
└── identity/
    ├── main.tf      → module "payment_workspace" (from resource_group)
    └── data.tf      → reads spoke_network + spoke_data states
```

Plus a new `.tfvars` file: `Deployment/Spokes/payment-service/dev.tfvars`

Plus new CI workflow steps in the pipeline that reference the new directories.

### Add a New Module

1. Create `Modules/new-module/`
2. Add `main.tf`, `variables.tf`, `outputs.tf`
3. Define clean input/output contracts
4. Call it from any workload's `main.tf`

### Enable State Locking

To prevent concurrent operations, integrate **DynamoDB-compatible locking**:

```hcl
backend "s3" {
  # ... existing config ...
  dynamodb_table = "terraform-state-locks"  # Requires a DynamoDB table
}
```

> Note: DigitalOcean doesn't offer DynamoDB. You'd need AWS DynamoDB or a custom locking solution.

---

## 📚 Related Documents

| Document | Description |
|----------|-------------|
| [README.md](../readme.md) | Project overview and quick start |
| [ci-cd-pipeline.md](ci-cd-pipeline.md) | CI/CD workflow deep dive |
| [reference-architecture.md](reference-architecture.md) | Enterprise reference patterns |
| [best-practices.md](best-practices.md) | Engineering standards and guidelines |
