📝 Repository Description
Production-grade Enterprise Infrastructure-as-Code (IaC) framework demonstrating modern Platform Engineering and DevSecOps principles on DigitalOcean via Terraform.

This repository implements a highly secure, completely decoupled Hub-and-Spoke architecture modeled after cloud landing zone frameworks. Infrastructure is split into distinct lifecycle boundaries—reusable module blueprints, global core networking foundations, and independent workload application spokes—to minimize blast radius and strictly enforce the separation of concerns. Complete with automated, state-isolated GitHub Actions CI/CD pipelines implementing plan-apply splits and strict immutability patterns.

🛡️ Key Architecture Highlights to Include:
Decoupled Structure: Complete isolation between underlying structural logic (Workload/) and runtime environment values (Deployment/).

State Matrix Management: Independent, isolated remote state tracking per layer via DigitalOcean Spaces (S3 API compatibility) to prevent state corruption.

Secure GitOps Pipeline: Reusable GitHub Actions workflows designed to run automated formatting checks, validation, and immutable plan artifact delivery before execution.