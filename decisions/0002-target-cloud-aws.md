# ADR-0002: Target cloud is AWS

- **Status:** Accepted
- **Date:** <TODO>
- **Deciders:** Team <name>

## Context
We must pick one target cloud. The brief stubs three primitives locally — object storage,
a relational database, and a cache — and asks us to "name things accordingly." We want the
mapping between our local `docker-compose` stand-ins and the cloud target to be as legible
as possible to the auditor and the CTO.

## Decision
Target **AWS**. The stand-ins map directly: **MinIO → S3**, **Postgres → RDS**,
**Redis → ElastiCache**. Compute target: containerized services on **ECS / App Runner**
(web app), **EventBridge Scheduler + ECS task** (batch), **RDS Postgres + read replica**
(reporting). IaC in **Terraform**.

## Consequences
- The local→cloud mapping is one-to-one and obvious in every file name.
- Secrets via AWS Secrets Manager / SSM (ADR-0003).
- We commit to AWS service vocabulary in The Options scoring (ECS vs EKS, etc.).

## Alternatives considered
- **Azure** (App Service / Container Apps, Blob, Azure DB for Postgres, Azure Cache) — viable;
  rejected only for mapping legibility, not capability.
- **GCP** (Cloud Run / GKE, Cloud Storage, Cloud SQL, Memorystore) — same reasoning.
