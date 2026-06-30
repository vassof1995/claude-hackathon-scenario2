# ADR-0005: Web-App Target Architecture — ECS Fargate + S3/CloudFront

- **Status:** Accepted
- **Date:** 2026-06-30
- **Deciders:** Contoso Migration Team

## Context
The web-app has two components: a Vue SPA (built by Vite, served by nginx) and a stateless
Spring Boot REST API (port 8080, Postgres app schema, /actuator/health endpoint).
A critical undocumented coupling (C1) shapes the architecture: nginx.conf contains
"location /api/ { proxy_pass http://web-api:8080 }" — a Docker-internal DNS reference.
When the SPA moves to S3, it can no longer resolve the Docker service name "web-api",
making the /api/* path unreachable without either CORS configuration or a cloud-native proxy.
Two obvious solutions both have cost: CORS requires a Vue frontend code change and complex
header management; a separate proxy service adds infrastructure complexity.

## Decision
Frontend: Re-platform to S3 bucket "contoso-web-frontend-s3" (versioned, SSE-S3, public access blocked)
fronted by a CloudFront distribution. C1 is resolved by an ordered CloudFront cache behavior
for path pattern "/api/*" that routes to the ALB origin with all caching disabled (TTL=0,
all headers/cookies/query strings forwarded). From the browser the /api/* path remains
same-origin — no CORS headers needed, no Vue code change, no new moving part.

API: Re-host to ECS Fargate (desired 2 tasks across 2 AZs, CPU 512/Memory 1024) behind an
Application Load Balancer. The same Spring Boot image deploys unchanged; only three env vars
swap: SPRING_DATASOURCE_URL, _USERNAME, and _PASSWORD are injected from AWS Secrets Manager
via the ECS task definition secrets block (never environment block). The ALB health check
uses GET /actuator/health (already implemented). An ECR repository (contoso/web-api) stores
the image. An assets bucket (contoso-web-assets-s3) is provisioned empty for future use.

## Consequences
Positive:
- Same-origin contract preserved — no CORS, no frontend code change
- Frontend scales globally at CloudFront edge with no ECS compute for static files
- API scales horizontally — stateless, ALB round-robin to 2+ tasks
- Routing rules (the /api/* behavior) live in Terraform, readable by ops and auditor

Risks and mitigations:
- RISK [HIGH]: CloudFront /api/* caching MUST be disabled (min/default/max TTL=0).
  A misconfiguration causes stale API reads. Smoke test asserts a mutation is visible
  on the next GET through the same URL path.
- RISK [LOW]: CloudFront cache invalidation (invalidate /*) is required on every
  frontend deploy. Must be wired into CI/CD.
- NOTE: nginx coupling C1 is only resolved in the cloud architecture. The local
  docker-compose intentionally keeps nginx proxy as the local stand-in — this is
  by design, not a gap.

## Alternatives Considered
1. AWS App Runner for API — rejected: no private subnet placement (data-tier SG isolation
   requires VPC), less control over ALB health check path, cannot be placed in the
   private-app subnet tier required by the VPC design.
2. Keep nginx on ECS fronting both frontend and API — rejected: static file serving on
   compute is expensive and unnecessary; CloudFront edge cache is lost; does not satisfy
   the CTO's "cloud-native, not lift-and-shift" requirement for the SPA component.
3. CORS + separate CloudFront domain for API — rejected: requires a Vue frontend code
   change (all fetch() calls would need absolute API URLs), introduces complex CORS
   preflight management, and makes the API publicly addressable at a separate domain
   (wider attack surface than an ALB in private subnets).
