# My Terraform Learning Journey on DigitalOcean 🚀

![DigitalOcean](https://img.shields.io/badge/Cloud-DigitalOcean-0060FF?logo=digitalocean)
![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform)
![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=githubactions)
![License](https://img.shields.io/badge/License-MIT-green)

**If you're learning Terraform and want to see a real (but not production) project that ties together Infrastructure as Code, GitOps, and cloud networking — you're in the right place.**

This repo is my personal learning sandbox. I built it to understand how Terraform works with DigitalOcean, how to structure infrastructure code properly, and how to set up an automated CI/CD pipeline that deploys infrastructure safely. I made a fictional app called **FinTrack** as the excuse to build all of this.

> **Disclaimer**: This is a **learning project**, not a production landing zone. I've made mistakes, taken shortcuts, and definitely done things that would make a senior DevOps engineer raise an eyebrow. But that's the point — I learned by doing.

---

## 📖 Table of Contents

- [Why I Built This](#-why-i-built-this)
- [What I Learned Along the Way](#-what-i-learned-along-the-way)
- [Architecture at a Glance](#-architecture-at-a-glance)
- [Repo Structure (What Goes Where)](#-repo-structure-what-goes-where)
- [Gotchas I Hit (So You Don't Have To)](#-gotchas-i-hit-so-you-dont-have-to)
- [Getting Started — Actually Running This](#-getting-started--actually-running-this)
- [If I Were Starting Over](#-if-i-were-starting-over)
- [Resources That Helped Me Learn](#-resources-that-helped-me-learn)

---

## 🧭 Why I Built This

I wanted to go from "I can run `terraform apply` on a single VM" to understanding:

- **How do you structure infrastructure code** when you have multiple environments, multiple teams, and multiple services?
- **What's the big deal about state files** — and why does everyone say "don't share one state file"?
- **How does GitOps actually work** in practice with Terraform?
- **How do you connect different pieces of infrastructure** — like a database knowing which VPC it's in — without creating a tangled mess?

So I invented a fake personal finance app called **FinTrack** and decided to build the infrastructure for it "the right way."

I chose **DigitalOcean** because:
- It's simpler than AWS/Azure for learning (fewer services, straightforward pricing)
- They have managed MongoDB, which I wanted to try
- Their Spaces object storage is S3-compatible, so I could practice with Terraform's S3 backend

I chose **Singapore (sgp1)** as the region because... well, because it was the only region which was available to create a S3 Bucket. No deeper reason than that.

---

## 💡 What I Learned Along the Way

### Infrastructure as Code Is More Than Just "Code That Makes Infrastructure"

I thought IaC meant "write some Terraform, run apply, done." What I actually learned:

| What I Thought | What I Learned |
|---------------|----------------|
| One big `main.tf` is fine | **No — split things into modules, layers, and state files** |
| State files are just metadata | **State files ARE your infrastructure — lose them and you're in trouble** |
| Plan and apply in one step | **Always split plan and apply — reviewing plans saves your bacon** |
| Secrets in variables are fine | **Never, ever commit secrets. Use GitHub Secrets or env vars** |
| Terraform fmt is optional | **It's not optional — CI will yell at you, and rightly so** |

### The "Aha" Moment: Separate State Files

My first attempt had everything in one state file. A mistake in the database layer would lock up the whole VPC. A plan for everything took 2+ minutes. I realized: **each logical piece of infrastructure should have its own state file**. That way:

- A corrupted state only breaks one piece
- Plans are fast (seconds, not minutes)
- I can destroy and recreate a layer without touching others

### GitOps Clicked When I Merged My First PR

Setting up GitHub Actions to run `terraform plan` on a PR and then `terraform apply` on merge felt magical the first time it worked. The key insight: **the plan binary is a promise**. You review the promise, then the pipeline executes it — exactly as reviewed, even if someone changed the code in between.

### The Dummy Region Fix Took Me 3 Hours to Debug

I spent an evening trying to figure out why `terraform init` kept hanging in CI. Turns out, the S3 backend driver needs a `region` parameter even when you're using DigitalOcean Spaces (which doesn't have AWS regions). Passing `-backend-config="region=us-east-1"` fixed it. More on this in the CI/CD docs.

---

## 🏛️ Architecture at a Glance

### The Big Idea: Hub-and-Spoke

Think of this like an office building:

- **The Hub** is the lobby, security desk, and shared utilities (like elevators and power). It's the central VPC network and the root project.
- **Each Spoke** is a separate company's office floor. They have their own rooms (servers), their own database closets, and their own door signs (projects).
- The companies on different floors can't mess with each other, but they all use the building's shared infrastructure.

Here's what that looks like in DigitalOcean:

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

### How the Layers Talk to Each Other

Each layer has its own state file stored in DigitalOcean Spaces. When one layer needs info from another (like "what's the VPC ID so I can put my database in it?"), it reads that layer's state using `data.terraform_remote_state`. 

But here's the key: **it can only READ, not WRITE**. The database layer reads the VPC ID from the network layer's state, but it can never modify the network layer's resources. This is called a **state bridge**, and it's what keeps everything safely decoupled.

```text
Hub Network (Core VPC)
    │
    │  reads hub_vpc_id
    ▼
Spoke Network (Droplets + Firewall)
    │
    │  reads spoke_vpc_id
    ▼
Spoke Data (MongoDB)
    │
    │  reads droplet_urns + database_urn
    ▼
Spoke Identity (Project Binding)
```

### The Three Parts of Every Environment

Every environment (currently just `dev` under the `fintrack` spoke) has three layers:

1. **Network** — The compute (Droplets) and firewall rules that protect them
2. **Data** — The managed MongoDB cluster, connected to the private network
3. **Identity** — A DigitalOcean Project that groups all the resources together

These are deployed in strict order because each depends on the previous one's outputs.

---

## 📂 Repo Structure (What Goes Where)

Here's how I organized everything. The idea was to separate **configuration** (what values to use) from **logic** (how to create resources) from **execution** (which resources to create):

```
.
├── .github/workflows/           # CI/CD pipeline files (GitHub Actions)
│   ├── fintrack-pipeline.yml    # Main orchestrator — decides what runs when
│   ├── terraform-plan.yml       # Reusable "plan" workflow
│   └── terraform-apply.yml      # Reusable "apply" workflow
│
├── Deployment/                   # Configuration values (.tfvars files)
│   ├── Core/
│   │   └── global.tfvars        # Hub settings (region, VPC CIDR, project name)
│   └── Spokes/
│       └── fintrack/
│           └── dev.tfvars       # FinTrack dev-specific settings
│
├── Modules/                      # Reusable Terraform building blocks
│   ├── droplet/                  # Creates virtual machines
│   ├── firewall/                 # Manages security rules
│   ├── networking/               # Creates VPC networks
│   ├── data/mongo_db/            # Sets up managed MongoDB
│   └── resource_group/           # Creates DigitalOcean Projects
│
├── Workload/                     # Actual infrastructure definitions
│   ├── Core/                     # The Hub — shared services
│   │   ├── network/              #   Hub VPC
│   │   ├── identity/             #   Hub Project
│   │   └── data/                 #   Hub Storage (placeholder)
│   └── Spokes/                   # Application environments
│       └── fintrack/
│           ├── network/          #   FinTrack Droplets + Firewall
│           ├── data/             #   FinTrack MongoDB
│           └── identity/         #   FinTrack Project binding
│
├── Docs/                         # 📚 Documentation
│   ├── architecture.md           # Deep dive into the architecture
│   ├── ci-cd-pipeline.md         # How the pipeline works
│   ├── reference-architecture.md # Ways to extend this project
│   └── best-practices.md         # Lessons learned the hard way
│
└── readme.md                     # ← You are here
```

> 💡 **My pattern**: Every workload directory has exactly 6 files — `main.tf`, `variables.tf`, `outputs.tf`, `data.tf`, `providers.tf`, and `backend.tf`. Once I established this pattern, navigating the repo became muscle memory.

---

## ⚠️ Gotchas I Hit (So You Don't Have To)

### 1. The Infamous Headless Init Hang

**The problem**: `terraform init` in CI would just hang forever with no error message.

**Why**: I was using partial S3 backend configuration (empty `backend "s3" {}`) and injecting the real values at init time. But the AWS S3 driver insists on a `region` parameter — and if you don't provide one, it prompts interactively. CI has no keyboard, so it hangs.

**The fix**: Always include `-backend-config="region=us-east-1"` in your `terraform init` command. It's a dummy value (DigitalOcean Spaces uses endpoints, not AWS regions), but it satisfies the SDK.

```bash
terraform init \
  -backend-config="bucket=<your-bucket>" \
  -backend-config="endpoint=sgp1.digitaloceanspaces.com" \
  -backend-config="key=<your-key>" \
  -backend-config="region=us-east-1"  # ← This line saves you hours
```

### 2. State Key Mismatch Between Layers

I had the pipeline writing state to `core/network.tfstate`, but my Core Identity layer's `data.tf` was reading from `core/network/global.tfstate`. Different key = different state file = my identity layer couldn't find the VPC.

**Lesson**: Every `data.terraform_remote_state` must reference the **exact same state key** that the pipeline uses. I documented the convention in `Docs/ci-cd-pipeline.md`.

### 3. SSH Hung on `terraform apply` on Windows

Terraform would prompt for a host key confirmation interactively in the CI pipeline, causing it to hang. The fix was setting `-input=false` on the apply command so it fails fast instead of hanging.

### 4. The VPC URN That Didn't Exist

I wrote the Core Identity layer to reference `hub_vpc_urn` from the Core Network state — but my networking module wasn't outputting a `vpc_urn` at all. The research subagent caught this one. I had to add `output "vpc_urn" { value = digitalocean_vpc.network.urn }` to the networking module.

---

## 🚀 Getting Started — Actually Running This

If you want to try this yourself, here's what you'll need and the rough steps.

### Prerequisites

| Tool | Why You Need It |
|------|----------------|
| [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0 | To run the infrastructure code |
| A [DigitalOcean account](https://cloud.digitalocean.com/) | Where everything runs |
| A [DigitalOcean Spaces bucket](https://www.digitalocean.com/products/spaces) | To store Terraform state files |
| A GitHub account | For the CI/CD pipeline |
| [Doctl CLI](https://docs.digitalocean.com/reference/doctl/) (optional) | For debugging from command line |

### Step 1: Create a Spaces Bucket

In your DigitalOcean account, create a Spaces bucket in the `sgp1` region. Name it something like `fintrack-tfstate-bucket`. Enable **Object Versioning** — this gives you automatic state file backups.

### Step 2: Generate API Credentials

Create a **DigitalOcean Personal Access Token** with read/write scope. Also generate a **Spaces Access Key** pair (under API → Spaces). Save these somewhere secure — you'll need them in the next step.

### Step 3: Set Up GitHub Secrets

In your GitHub repo, go to Settings → Secrets and variables → Actions and add:

| Secret | What It Is |
|--------|------------|
| `DIGITALOCEAN_TOKEN` | Your DO personal access token |
| `DO_SPACES_ACCESS_KEY` | Spaces access key |
| `DO_SPACES_SECRET_KEY` | Spaces secret key |
| `DO_SPACES_BUCKET` | Your bucket name (e.g., `fintrack-tfstate-bucket`) |

### Step 4: Bootstrap the Hub (One-Time Manual Step)

The Hub infrastructure has no upstream dependencies, so it needs to be deployed first manually:

```bash
# Deploy Core Network
cd Workload/Core/network
terraform init -backend-config="bucket=<your-bucket>" \
               -backend-config="endpoint=sgp1.digitaloceanspaces.com" \
               -backend-config="key=core/network.tfstate" \
               -backend-config="access_key=<your-access-key>" \
               -backend-config="secret_key=<your-secret-key>" \
               -backend-config="region=us-east-1"
terraform apply -var-file=../../../Deployment/Core/global.tfvars

# Deploy Core Identity
cd ../identity
terraform init -backend-config="bucket=<your-bucket>" \
               -backend-config="endpoint=sgp1.digitaloceanspaces.com" \
               -backend-config="key=core/identity.tfstate" \
               -backend-config="access_key=<your-access-key>" \
               -backend-config="secret_key=<your-secret-key>" \
               -backend-config="region=us-east-1"
terraform apply -var-file=../../../Deployment/Core/global.tfvars
```

### Step 5: Push to GitHub and Let CI Take Over

Once the Hub is deployed, push everything to GitHub. Open a PR from a feature branch, and the CI pipeline will:
1. Run `terraform fmt -check` to validate formatting
2. Initialize Terraform with the Spaces backend
3. Run `terraform validate` to check syntax
4. Execute `terraform plan` and upload the plan as an artifact

Merge the PR and the pipeline will automatically apply the plan.

### Local Development Workflow

For local testing without triggering CI:

```bash
# 1. Create a feature branch
git checkout -b feature/my-change

# 2. Make changes

# 3. Format everything
terraform fmt -recursive

# 4. Validate locally
cd Workload/Spokes/fintrack/network
terraform init -backend=false
terraform validate

# 5. Commit and push
git add .
git commit -m "feat: describe your change"
git push origin feature/my-change

# 6. Open a PR → CI does the rest
```

---

## 🔁 If I Were Starting Over

Looking back, here's what I'd do differently:

1. **Start with the state key convention documented first.** Most of my bugs were state key mismatches because I didn't decide on a naming convention before writing code.

2. **Test the CI pipeline with a dummy resource first.** I spent way too long debugging the Headless Init Fix while also debugging Terraform config issues. A test that just creates a simple Spaces bucket would have isolated the problems.

3. **Write more module tests.** The research subagent found issues like the duplicate resource binding in `resource_group/main.tf` and the MongoDB version string format. Unit tests or `terraform validate` on modules would catch these.

4. **Use `skip_requesting_account_id = true` everywhere from the start.** Some backend configs have it, some don't. Just add it to all S3 backend configs for DigitalOcean Spaces.

5. **Document as I go, not at the end.** I'm writing these docs after finishing the code, and I've already forgotten why I made some decisions. Future me would appreciate inline comments.

---

## 📚 Resources That Helped Me Learn

These are the resources I used while building this:

- [Official Terraform DigitalOcean Provider Docs](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs) — My most-visited page
- [HashiCorp Learn: Terraform on DigitalOcean](https://developer.hashicorp.com/terraform/tutorials/cloud/digitalocean) — Good starting tutorials
- [DigitalOcean Community Tutorials](https://www.digitalocean.com/community/tutorials) — Practical, example-driven
- [Terraform S3 Backend Configuration](https://developer.hashicorp.com/terraform/language/settings/backends/s3) — For understanding the `region` dummy value fix
- [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions) — For the CI/CD pipeline
- [Context Mode (this agent harness)](https://github.com/earendil-works/pi-coding-agent) — Used to orchestrate the subagents that helped build and research this repo

### Doc Index

| Document | What It Covers |
|----------|---------------|
| [Docs/architecture.md](Docs/architecture.md) | Hub-and-Spoke explained like you're 5, state bridges, module design, and all my design decisions |
| [Docs/ci-cd-pipeline.md](Docs/ci-cd-pipeline.md) | The GitOps pipeline, the Headless Init Fix saga, and troubleshooting your own pipeline |
| [Docs/reference-architecture.md](Docs/reference-architecture.md) | Ways to extend this — multi-spoke, multi-region, cost estimates, production hardening |
| [Docs/best-practices.md](Docs/best-practices.md) | Lessons I learned the hard way — state management, naming, code review, and more |

---

## 🤝 Contributing

This is a learning project, but if you spot a bug or have an idea for improvement, feel free to:
1. Fork the repo
2. Create a feature branch
3. Make your changes (and run `terraform fmt -recursive`!)
4. Open a Pull Request

I'm still learning too — I'd love to hear what you'd do differently.

---

## 📄 License

MIT — See [LICENSE](LICENSE) file for details.
