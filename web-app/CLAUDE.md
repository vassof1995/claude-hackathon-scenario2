# CLAUDE.md — web-app workload

Customer-facing web app. Target: containerized service on **ECS / App Runner** behind an ALB.

## Guidance for edits here
- **Dockerfile must be:** multi-stage, **non-root** user, with a `/healthz` (or `/health`)
  endpoint. The same image deploys to AWS with a **config swap, not a rebuild** — all
  environment-specific values come from env vars, never baked into the image.
- Talks to: Postgres (→ RDS), Redis (→ ElastiCache), MinIO (→ S3). Use env vars for every
  endpoint — **no hardcoded hosts/IPs** (a hardcoded IP is one of the Discovery gremlins;
  don't reintroduce it here).
- Healthcheck must verify downstream reachability enough to be meaningful, not just return 200.
- Keep secrets out of the image and out of `docker-compose.yml` — reference `.env` locally,
  Secrets Manager in cloud.
