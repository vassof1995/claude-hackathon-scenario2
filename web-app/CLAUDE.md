# CLAUDE.md — web-app workload

## What this is
Customer-facing workload: Vue SPA frontend + Spring Boot REST API. Two containers locally, three AWS services in cloud (S3, CloudFront, ECS Fargate+ALB).

## Challenges covered
- Challenge 4 (The Container): legacy/web-app/api/Dockerfile and legacy/web-app/frontend/Dockerfile
- Challenge 5 (The Foundation): infra/modules/ecs-web-api/, infra/modules/s3-cloudfront/, infra/envs/prod/web-app.tf

## Local development
Start: docker compose up web-frontend web-api postgres-rds minio-s3
- Frontend: http://localhost:8080
- API direct: http://localhost:8081/actuator/health and /api/customers
- API via nginx proxy: http://localhost:8080/api/customers (coupling C1 locally)

## Cloud target
- Frontend: S3 "contoso-web-frontend-s3" + CloudFront distribution
- API: ECS cluster "contoso-web-api", 2 tasks/2 AZs, behind ALB
- Secrets: AWS Secrets Manager paths contoso/web-api/db-{url,username,password}

## Coupling C1 — nginx /api/ proxy
LOCAL:  nginx.conf proxies /api/ → http://web-api:8080 (same-origin, no CORS)
CLOUD:  CloudFront ordered_cache_behavior path="/api/*" → ALB origin, TTL=0
RULE:   NEVER add CORS headers. NEVER change the Vue app to use absolute API URLs.
        The proxy/CloudFront behavior is what keeps same-origin without code changes.

## Secrets rule
LOCAL: .env (git-ignored), SPRING_DATASOURCE_* env vars
CLOUD: ECS task definition uses secrets block referencing Secrets Manager ARNs
NEVER put DB passwords in docker-compose.yml, Dockerfile, or any committed file.

## Health check
GET /actuator/health → HTTP 200 {"status":"UP"}
Used by: ALB health check, ECS container healthCheck, docker compose healthcheck.
