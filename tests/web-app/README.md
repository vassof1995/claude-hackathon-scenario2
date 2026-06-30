# Web-App Smoke Tests

## Purpose

Defines "migration succeeded" for the **web-app** workload of the Contoso Financial cloud migration.
The suite catches both functional correctness and the undocumented couplings found in Discovery —
so it is not just theatre. Test 4 (C1 coupling) is the most critical: it is the one check that
would catch the nginx `/api/` dependency if it were broken during migration.

## How to run

```bash
docker compose up -d
sleep 90   # wait for JVM startup and Flyway migration
./tests/web-app/smoke_test.sh
```

Override defaults via environment variables:

```bash
FRONTEND_URL=http://localhost:8080 API_URL=http://localhost:8081 ./tests/web-app/smoke_test.sh
```

## Test coverage

| # | Test | What it catches | Why it matters |
|---|------|-----------------|----------------|
| 1 | API health `/actuator/health` returns HTTP 200 + `"UP"` | API container not started, DB connection failed, Spring context broken | Gate: nothing else is useful if the API is down |
| 2 | `GET /api/customers` returns non-empty JSON array | Flyway migration not run, seed data missing, DB unreachable | Contract: downstream batch and reporting-db workloads depend on this data |
| 3 | `GET /` returns HTTP 200 | nginx / frontend container not serving static assets | Basic reachability of the SPA |
| 4 | `GET FRONTEND_URL/api/customers` returns HTTP 200 (C1 coupling) | nginx reverse-proxy rule `proxy_pass http://web-api:8080` from Discovery | **Most critical migration risk** — in cloud this path becomes CloudFront `/api/*` → ALB |
| 5 | No `Access-Control-Allow-Origin` header on `/api/` path | Same-origin contract broken (CORS leaking) | Cloud architecture preserves same-origin via CloudFront; adding CORS would be a regression |

## Local vs cloud differences

| Aspect | Local (docker compose) | Cloud (post-cutover) |
|--------|------------------------|----------------------|
| `FRONTEND_URL` | `http://localhost:8080` (nginx) | CloudFront distribution URL |
| `API_URL` | `http://localhost:8081` (Spring Boot direct) | ALB DNS name |
| `/api/*` routing | nginx `proxy_pass http://web-api:8080` | CloudFront ordered behavior → ALB |
| TLS | none | CloudFront enforces HTTPS (redirect-to-https) |
| Health check path | same | same (`/actuator/health`) |

For post-cutover validation set both env vars to the cloud endpoints and re-run this script unchanged.

## C1 coupling note

Discovery found an undocumented nginx rule:

```
location /api/ {
    proxy_pass http://web-api:8080;
}
```

Without Test 4 a pure smoke test would confirm the frontend loads but miss the fact that
`/api/` calls never reach the API — the most common breakage during a lift-and-shift.
The cloud fix (CloudFront `/api/*` ordered behavior → ALB) preserves the same-origin contract
so no CORS headers and no frontend code changes are needed (ADR documented in `/decisions/`).
