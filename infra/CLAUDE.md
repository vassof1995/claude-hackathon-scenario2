# CLAUDE.md — infra (Infrastructure-as-Code)

Terraform for the full AWS target architecture. **It won't deploy live — but it must read
right.** The auditor reads this folder first.

## Non-negotiables
- **Idempotent.** `plan` after `apply` shows no drift.
- **No hardcoded secrets.** Ever. Use **AWS Secrets Manager / SSM Parameter Store** and pass
  references, not values. A `PreToolUse` hook blocks any edit that writes a plaintext secret
  here (see ADR-0003). If the hook fires, fix the approach — don't work around it.
- **Remote state story** that isn't "check it in" — S3 backend + DynamoDB lock (describe it
  even though we don't stand it up live). State files are git-ignored.
- **Tag everything** (owner, workload, env, cost-center). Missing tags is a known-bad pattern
  the Scorecard checks for.
- **Least privilege IAM.** No `*:*`. Over-permissive IAM and open security groups (`0.0.0.0/0`
  on sensitive ports) are known-bad patterns the eval harness flags.

## Layout (suggested)
```
infra/
  modules/        # reusable: network, ecs, rds, elasticache, s3
  envs/
    local/        # maps to docker-compose stand-ins
    prod/         # the real target shape (not applied)
```
