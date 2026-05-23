# Reference Architecture

> **Audience**: Enterprise architects, platform engineers, and technical decision-makers evaluating or extending this infrastructure pattern.

---

## Table of Contents

- [Executive Summary](#-executive-summary)
- [Architecture Decision Records](#-architecture-decision-records)
- [Enterprise Hub-and-Spoke Topology](#-enterprise-hub-and-spoke-topology)
- [Multi-Environment Strategy](#-multi-environment-strategy)
- [Multi-Spoke Organization](#-multi-spoke-organization)
- [Production Hardening](#-production-hardening)
- [Disaster Recovery & Business Continuity](#-disaster-recovery--business-continuity)
- [Cost Optimization Patterns](#-cost-optimization-patterns)
- [Observability & Monitoring](#-observability--monitoring)
- [Compliance & Governance](#-compliance--governance)
- [Team Topology & Ownership](#-team-topology--ownership)
- [Migration Path: Monolith to Hub-and-Spoke](#-migration-path-monolith-to-hub-and-spoke)
- [Frequently Asked Questions](#-frequently-asked-questions)

---

## 📋 Executive Summary

### Problem Statement

Organizations deploying to DigitalOcean often start with a single VPC containing all resources. As the application portfolio grows, this creates:

- **State file bloat** — One massive Terraform state that takes minutes to plan
- **High blast radius** — Any infrastructure change risks the entire environment
- **Team coupling** — One team's deployment blocks another's
- **Configuration drift** — Copy-pasted configurations diverge over time

### Solution: Hub-and-Spoke Landing Zone

This reference architecture provides:

| Concern | Solution |
|---------|----------|
| State management | Isolated per-layer state files in DigitalOcean Spaces |
| Blast radius | Independent failure domains per spoke and per layer |
| Configuration | Centralized `.tfvars` matrix with environment-specific values |
| CI/CD | GitOps pipeline with Plan-Apply split for auditability |
| Reusability | Composable Terraform modules for consistent resource creation |
| Security | Zero secrets in code, private network database, committed firewall rules |

### When to Use This Pattern

| ✅ Use This | ❌ Don't Use This |
|------------|-------------------|
| You have 2+ applications on DigitalOcean | You have a single, simple app on one VM |
| You need environment isolation (dev/staging/prod) | You're prototyping or in early MVP stage |
| Multiple teams deploy infrastructure | You're the solo operator |
| You need audit trails for infrastructure changes | Your compliance requirements are minimal |
| You want to standardize resource creation | You prefer click-ops in the DigitalOcean console |

---

## 📐 Architecture Decision Records

### ADR-001: DigitalOcean as Primary Cloud Provider

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Context** | Need a cloud provider for FinTrack application |
| **Decision** | Use DigitalOcean as the primary (and only) cloud provider |
| **Rationale** | Simple pricing, managed Kubernetes and databases, Spaces for S3-compatible storage, Singapore region availability |
| **Consequences** | No native state locking (no DynamoDB), fewer managed services than AWS/Azure/GCP |

### ADR-002: Terraform over Pulumi / CDK / Crossplane

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Context** | Choose Infrastructure as Code tool |
| **Decision** | Terraform (HashiCorp) — version >= 1.5.0 |
| **Rationale** | Industry standard, wide DigitalOcean provider support, `terraform_remote_state` for data bridges, mature CI/CD integration |
| **Consequences** | HCL language (domain-specific), state management required |

### ADR-003: S3-Compatible Backend over Terraform Cloud

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Context** | Where to store Terraform state files |
| **Decision** | DigitalOcean Spaces (S3-compatible object storage) |
| **Rationale** | Same provider, same region (sgp1), minimal latency, no additional third-party dependency |
| **Consequences** | No native state locking, need `skip_credentials_validation` and `skip_metadata_api_check` flags |

### ADR-004: Per-Layer State Isolation

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Context** | How many Terraform state files |
| **Decision** | One state file per layer (6 total: 3 hub + 3 spoke) |
| **Rationale** | Minimizes blast radius, enables parallel CI jobs, reduces plan time |
| **Consequences** | More complex data flow (remote state data sources), strict provisioning order |

### ADR-005: State Bridge via terraform_remote_state

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Context** | How layers share information |
| **Decision** | `data "terraform_remote_state"` with S3 backend config |
| **Rationale** | Read-only sharing, no coupling between layers, works within same Terraform version |
| **Consequences** | Each layer must know upstream state key, no type safety across state boundaries |

### ADR-006: GitHub Actions over Self-Hosted CI

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Context** | Where to run CI/CD |
| **Decision** | GitHub Actions with reusable workflows |
| **Rationale** | Co-located with code, managed runners, `workflow_call` for DRY patterns, free for public repos |
| **Consequences** | 6-hour execution limit on workflows, runner environment not customizable beyond Ubuntu |

### ADR-007: MongoDB 7.0 as Database Engine

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Context** | Application data store |
| **Decision** | DigitalOcean Managed MongoDB 7.0 |
| **Rationale** | Document model fits FinTrack app, managed backup/failover, private network support |
| **Consequences** | Vendor lock-in to DO managed DB (compared to self-hosted), no cross-region replication |

---

## 🏢 Enterprise Hub-and-Spoke Topology

### Multi-Environment, Multi-Spoke Layout

For a true enterprise deployment, the topology expands to:

```
                        ┌──────────────────────────────────┐
                        │          DIGITALOCEAN            │
                        │          Account Root            │
                        └──────────────────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
              ▼                       ▼                       ▼
    ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
    │   Dev Hub        │   │   Staging Hub    │   │   Production Hub │
    │  sgp1/dev        │   │  sgp1/staging    │   │  sgp1/prod       │
    └────────┬─────────┘   └────────┬─────────┘   └────────┬─────────┘
             │                      │                      │
     ┌───────┼───────┐      ┌───────┼───────┐      ┌───────┼───────┐
     │       │       │      │       │       │      │       │       │
     ▼       ▼       ▼      ▼       ▼       ▼      ▼       ▼       ▼
   ┌───┐   ┌───┐   ┌───┐ ┌───┐   ┌───┐   ┌───┐ ┌───┐   ┌───┐   ┌───┐
   │ F │   │ P │   │ B │ │ F │   │ P │   │ B │ │ F │   │ P │   │ B │
   │ i │   │ a │   │ i │ │ i │   │ a │   │ i │ │ i │   │ a │   │ i │
   │ n │   │ y │   │ l │ │ n │   │ y │   │ l │ │ n │   │ y │   │ l │
   │ T │   │ m │   │ l │ │ T │   │ m │   │ l │ │ T │   │ m │   │ l │
   │ r │   │ e │   │   │ │ r │   │ e │   │   │ │ r │   │ e │   │   │
   │ a │   │ n │   │   │ │ a │   │ n │   │   │ │ a │   │ n │   │   │
   │ c │   │ t │   │   │ │ c │   │ t │   │   │ │ c │   │ t │   │   │
   │ k │   │ s │   │   │ │ k │   │ s │   │   │ │ k │   │ s │   │   │
   └───┘   └───┘   └───┘ └───┘   └───┘   └───┘ └───┘   └───┘   └───┘
```

Each environment (dev/staging/prod) gets:
- Its own Hub VPC (different CIDR blocks to avoid peering conflicts)
- Its own Spaces bucket for state files
- All three spokes scoped to that environment

### CIDR Allocation Strategy

| Environment | Hub VPC CIDR | Purpose |
|-------------|-------------|---------|
| Dev | `10.0.0.0/16` | Development and testing |
| Staging | `10.64.0.0/16` | Pre-production validation |
| Production | `10.128.0.0/16` | Live customer traffic |

> Staggered CIDR blocks leave room for VPC peering between environments if needed.

---

## 🌍 Multi-Environment Strategy

### Environment Matrix

| Dimension | Dev | Staging | Production |
|-----------|-----|---------|------------|
| **Purpose** | Feature development & testing | Pre-production validation | Live customer traffic |
| **Droplet Size** | `s-1vcpu-1gb` | `s-2vcpu-2gb` | `s-4vcpu-8gb` |
| **Instance Count** | 1 | 2 | 3+ |
| **DB Node Count** | 1 (single node) | 2 | 3 (replica set) |
| **DB Size** | `db-s-1vcpu-1gb` | `db-s-2vcpu-2gb` | `db-s-4vcpu-8gb` |
| **SSL/TLS** | Self-signed | Let's Encrypt | Paid certificate |
| **Monitoring** | Basic | Detailed | Detailed + Alerts |
| **Backup Window** | None | Daily | Hourly |
| **Deploy Trigger** | PR to main | Push to staging | Push to production |

### Git Branch Strategy

```text
main           ← Dev environment (PR → plan, merge → apply)
  └── staging  ← Staging environment (merge → apply)
       └── production  ← Production environment (merge → apply)
```

Each branch has its own GitHub Actions workflow that applies to the corresponding environment.

### State Bucket Per Environment

```text
fintrack-tfstate-bucket-dev          # Dev environment state
fintrack-tfstate-bucket-staging      # Staging environment state
fintrack-tfstate-bucket-production   # Production environment state
```

> **Critical**: Never share a state bucket across environments. A mistake in dev should never corrupt production state.

---

## 🧩 Multi-Spoke Organization

### Spoke Grouping Patterns

| Pattern | Description | Best For |
|---------|-------------|----------|
| **By Application** | Each app = one spoke | Microservices, multiple products |
| **By Team** | Each team = one spoke | Platform teams, domain ownership |
| **By Sensitivity** | Low/medium/high = different spokes | Compliance, PCI, HIPAA |
| **By Lifecycle** | Experimental vs stable spokes | Fast-moving vs mature apps |

### Spoke Naming Convention

```text
{app-name}-{environment}

Examples:
fintrack-dev
payment-service-dev
billing-engine-staging
notification-service-prod
```

### Inter-Spoke Communication

Currently, spokes don't communicate directly — they all connect through the Hub VPC. For inter-spoke communication:

1. **VPC Peering** — The Hub VPC peers with each spoke, but spokes peer through the hub
2. **DNS Resolution** — Use private DNS names for service discovery
3. **API Gateway** — Route inter-service calls through an API gateway in the hub

---

## 🛡️ Production Hardening

### Network Hardening

| Measure | Implementation | Priority |
|---------|---------------|----------|
| **Restrict SSH Source** | Change firewall `source_addresses` from `0.0.0.0/0` to corporate VPN CIDR | High |
| **Database Private Only** | Already enforced — no public endpoint | High |
| **WAF / CDN** | Add Cloudflare or DO CDN in front of HTTP(S) | Medium |
| **DDoS Protection** | Enable DigitalOcean DDoS protection | Medium |
| **Load Balancer** | Replace single droplet with DO Load Balancer + auto-scaling | Medium |
| **TLS Everywhere** | Terminate TLS at load balancer or droplets | High |

### Database Hardening

| Measure | Implementation |
|---------|---------------|
| **Node Count** | 3-node replica set for automatic failover |
| **Backup** | Enable automated daily backups with 7-day retention |
| **Maintenance Window** | Schedule during low-traffic hours (e.g., 2-4 AM SGT) |
| **Connection Pooling** | Use PgBouncer or MongoDB driver connection pooling |
| **SSL/TLS** | Enforce TLS for all client connections |
| **Audit Logging** | Enable MongoDB audit log for compliance |

### CI/CD Hardening

| Measure | Implementation |
|---------|---------------|
| **Branch Protection** | Require PR reviews, status checks, no direct pushes to `main` |
| **Plan Review Required** | Make pipeline a required check before merge |
| **Secret Scanning** | Enable GitHub secret scanning on the repo |
| **Deployment Gates** | Add manual approval step for production applies |
| **Deploy Freeze** | Script to block deploys during freeze windows |

### Production .tfvars Example

```hcl
# Deployment/Spokes/fintrack/prod.tfvars
region             = "sgp1"
environment        = "prod"
app_name           = "fintrack"
state_bucket_name  = "fintrack-tfstate-bucket-production"

# Compute — Highly available, adequate resources
droplet_size       = "s-4vcpu-8gb"
instance_count     = 3

# Database — Multi-node for HA, adequate sizing
db_size_slug       = "db-s-4vcpu-8gb"
db_node_count      = 3
initial_database   = "fintrack_production_store"
```

---

## 🔄 Disaster Recovery & Business Continuity

### Recovery Point Objective (RPO) & Recovery Time Objective (RTO)

| Tier | RPO | RTO | Strategy |
|------|-----|-----|----------|
| **Production** | 1 hour | 4 hours | Automated backup + infrastructure-as-code redeploy |
| **Staging** | 24 hours | 8 hours | Daily backup + manual redeploy |
| **Dev** | None | 24 hours | Redeploy from scratch |

### Backup Strategy

| Resource | Backup Method | Frequency | Retention |
|----------|--------------|-----------|-----------|
| Terraform State | DigitalOcean Spaces versioning | Every write | 30 days |
| MongoDB | DigitalOcean automated backups | Daily | 7 days |
| Application Data | Application-level export | Hourly | 14 days |
| Configuration | Git repository | Every commit | Permanent |

### Recovery Playbook

```bash
# 1. Restore Terraform state from Spaces versioning (if corrupted)
# 2. Redeploy infrastructure from code:
cd Workload/Core/network
terraform init ... && terraform apply -var-file=../../Deployment/Core/global.tfvars

cd Workload/Core/identity
terraform init ... && terraform apply -var-file=../../Deployment/Core/global.tfvars

# 3. Repeat for each spoke layer in order (network → data → identity)
# 4. Restore MongoDB data from automated backup
# 5. Verify application connectivity
# 6. Update DNS records if IPs changed
```

### State File Recovery

DigitalOcean Spaces supports **object versioning** — every state file write creates a new version:

```
fintrack-tfstate-bucket/
└── spokes/fintrack/network.tfstate
    ├── Version 1: 2026-05-01 (original)
    ├── Version 2: 2026-05-10 (added droplet)
    ├── Version 3: 2026-05-15 (removed droplet — oops!)
    └── Version 2 restored ←
```

To restore:
1. Open Spaces bucket in DO console
2. Navigate to the `.tfstate` file
3. Click "Version History"
4. Restore the version before the corruption

---

## 💰 Cost Optimization Patterns

### Dev Environment Cost Savings

| Strategy | Savings | Implementation |
|----------|---------|---------------|
| **Single DB node** | ~60% vs 3-node | `db_node_count = 1` in dev |
| **Smallest droplet** | ~75% vs prod | `droplet_size = "s-1vcpu-1gb"` |
| **Scheduled shutdown** | ~65% (off 16h/day) | DigitalOcean droplet schedule |
| **No backups** | Storage cost only | Disable automated backups in dev |

### Estimated Monthly Costs

| Environment | Droplets | Database | Spaces | Total (est.) |
|-------------|----------|----------|--------|-------------|
| Dev (1 app) | $6 (1× $6) | $15 (1× $15) | $5 | **~$26/mo** |
| Staging (1 app) | $24 (2× $12) | $60 (2× $30) | $5 | **~$89/mo** |
| Production (1 app) | $72 (3× $24) | $180 (3× $60) | $5 | **~$257/mo** |
| **All 3 envs, 1 app** | | | | **~$372/mo** |

> Add ~$10-20 per additional spoke per environment.

### Right-Sizing Guidelines

| Usage Profile | Droplet Size | DB Size |
|---------------|-------------|---------|
| MVP / Prototype | `s-1vcpu-1gb` ($6) | `db-s-1vcpu-1gb` ($15) |
| Low traffic (<1K req/s) | `s-2vcpu-2gb` ($12) | `db-s-2vcpu-2gb` ($30) |
| Medium traffic (<10K req/s) | `s-4vcpu-8gb` ($48) | `db-s-4vcpu-8gb` ($120) |
| High traffic (>10K req/s) | `s-8vcpu-16gb` ($96) | `db-s-8vcpu-16gb` ($360) |

---

## 📊 Observability & Monitoring

### DigitalOcean Built-in Monitoring

| Resource | Metrics Available |
|----------|------------------|
| Droplet | CPU, memory, disk I/O, network, GPU (if applicable) |
| Database | CPU, memory, disk space, queries per second, connections |
| Spaces | Object count, storage used, bandwidth |

### Recommended Alerting Rules

| Alert | Threshold | Action |
|-------|-----------|--------|
| Droplet CPU > 80% | 5-minute average | Scale up or out |
| Droplet memory > 85% | 5-minute average | Scale up or optimize |
| Database connections > 80% of max | 5-minute average | Increase connection limit or scale |
| Disk usage > 85% | Instant | Clean up or increase volume |
| Backup failure | Any | Investigate and re-trigger |
| Terraform apply failure | Any | Check CI logs and state |

### Logging Strategy

| Log Source | Collection | Retention |
|-----------|-----------|-----------|
| Application logs | DO App Platform or self-hosted ELK | 30 days |
| System logs (droplet) | `journald` → remote syslog | 90 days |
| Database logs | DigitalOcean managed DB logs | 7 days |
| CI/CD logs | GitHub Actions | 90 days (or export to archive) |

---

## 📜 Compliance & Governance

### Infrastructure Change Governance

| Change Type | Required Approvals | Process |
|-------------|-------------------|---------|
| Module change (shared logic) | 2 senior engineers | PR with full plan output review |
| Variable value change | 1 engineer | PR with plan output |
| Environment promotion | DevOps lead | Separate PR for each env |
| New spoke (new app) | Architecture review | ADR + PR with plan |
| Hub infrastructure change | Platform team lead | ADR + PR + dry run |

### Audit Trail

Every infrastructure change is captured in:

| Artifact | What It Records | Where |
|----------|----------------|-------|
| Git commit history | Who changed what, when | GitHub |
| PR history | Review comments, plan output | GitHub |
| GitHub Actions logs | Exact `terraform plan/apply` output | GitHub (90 days) |
| Terraform state | Final state of every resource | DigitalOcean Spaces |
| DigitalOcean audit log | API calls to DO | DO control panel |

### Compliance Mapping

| Control | Implementation |
|---------|---------------|
| **Change Management** | All changes via PR with required reviews |
| **Separation of Duties** | Plan runs in CI, apply requires merge (different phase) |
| **Access Control** | Secrets in GitHub, not in code |
| **Data Isolation** | Each environment has separate state and resources |
| **Backup & Recovery** | Automated DB backups, Terraform state versioning |
| **Incident Response** | Infrastructure can be redeployed from Git in minutes |

---

## 👥 Team Topology & Ownership

### Recommended Team Structure

```
┌──────────────────────────────────────────────────┐
│              Platform Engineering Team            │
│           (Owns Hub, Modules, Pipeline)           │
└──────────────────────────────────────────────────┘
                    │
    ┌───────────────┼───────────────┐
    │               │               │
    ▼               ▼               ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│  Team A  │ │  Team B  │ │  Team C  │
│ FinTrack │ │ Payments │ │ Billing  │
│ (Spoke)  │ │ (Spoke)  │ │ (Spoke)  │
└──────────┘ └──────────┘ └──────────┘
```

| Team | Owns | Can Modify | Cannot Modify |
|------|------|-----------|---------------|
| **Platform** | Hub, Modules, Pipeline | Any Terraform logic | App-specific `.tfvars` |
| **App Team A** | Their spoke's `.tfvars` | Their spoke's variable values | Module code, Hub |
| **App Team B** | Their spoke's `.tfvars` | Their spoke's variable values | Module code, Hub |

### Responsibility Matrix

| Activity | Platform Team | App Team |
|----------|--------------|----------|
| Create new module | ✅ | ❌ |
| Modify module behavior | ✅ | ❌ |
| Update Terraform version | ✅ | ❌ |
| Change CI/CD pipeline | ✅ | ❌ |
| Change VPC CIDR | ✅ | ❌ |
| Set droplet size in dev | ❌ | ✅ |
| Set instance count | ❌ | ✅ |
| Add database indexes | ❌ | ✅ |
| Tune firewall rules | ❌ | ✅ (within agreed bounds) |

---

## 🚚 Migration Path: Monolith to Hub-and-Spoke

### Phase 1: Hub First (Week 1)

```
✅ Create Core Hub VPC
✅ Create Core Identity (Project)
✅ Deploy Hub manually
✅ Set up CI/CD pipeline
```

### Phase 2: First Spoke (Week 2)

```
✅ Create FinTrack spoke directories
✅ Extract existing infrastructure into Terraform modules
✅ Import existing resources into state
✅ Run pipeline — first successful plan+apply
```

### Phase 3: Expand (Week 3+)

```
✅ Add second spoke (new application or migration)
✅ Add staging environment
✅ Add production environment
✅ Set up monitoring and alerting
```

### Importing Existing Resources

If you have existing DigitalOcean resources outside Terraform:

```bash
# 1. Write the Terraform configuration matching the existing resource
# 2. Import it into state:
terraform import digitalocean_droplet.vm <existing-droplet-id>
terraform import digitalocean_vpc.network <existing-vpc-id>
# 3. Run terraform plan to verify state matches (no changes expected)
# 4. Run terraform apply to adopt the resource under Terraform management
```

---

## ❓ Frequently Asked Questions

### Can I use a different region?

Yes. Change `region` in `global.tfvars` and `dev.tfvars` to any DO region slug (e.g., `nyc1`, `ams3`, `fra1`). Update the Spaces endpoint accordingly (`nyc1.digitaloceanspaces.com`, etc.).

### Can I add Kubernetes (DOKS) instead of Droplets?

Yes. Create a new module `Modules/doks/` that provisions a DigitalOcean Kubernetes cluster. Replace the droplet module call in the spoke network layer with the DOKS module call. The identity layer still receives URNs for project binding.

### How do I handle secrets like database passwords?

For true secrets management, integrate **HashiCorp Vault** or **DO's built-in database credential rotation**. The current pipeline creates database credentials that Terraform stores in state — access them via `terraform output` in a secure channel.

### What if I need state locking?

DigitalOcean Spaces doesn't offer native locking. Options:
1. Use a DynamoDB table in AWS just for locks (cross-provider, but works)
2. Use Terraform Cloud's free tier for state management with locking
3. Implement a locking mechanism using Spaces object leases (custom solution)
4. Accept the risk (single-operator scenarios only)

### Can this pattern work with AWS / GCP?

The **architecture pattern** is cloud-agnostic, but the modules and provider configurations are DigitalOcean-specific. To adapt:
1. Replace `provider "digitalocean"` with the target cloud provider
2. Rewrite modules to use the target cloud's resources
3. Keep the Hub-and-Spoke layout, state isolation, and CI/CD patterns unchanged

### How do I handle database schema migrations?

Database schema migrations are **application concerns**, not infrastructure concerns. Use a migration tool like `migrate`, `golang-migrate`, or Alembic as part of the application deployment process — not in Terraform.

### Why not use Terraform workspaces?

Terraform workspaces share the same backend configuration and code, just with different state files. This architecture uses **completely separate state files** with different keys. Workspaces are useful for simple dev/prod splits, but the per-layer isolation here is more granular than what workspaces provide.

---

## 📚 Related Documents

| Document | Description |
|----------|-------------|
| [README.md](../readme.md) | Project overview and quick start |
| [architecture.md](architecture.md) | Architecture deep dive |
| [ci-cd-pipeline.md](ci-cd-pipeline.md) | CI/CD workflow deep dive |
| [best-practices.md](best-practices.md) | Engineering standards and guidelines |
