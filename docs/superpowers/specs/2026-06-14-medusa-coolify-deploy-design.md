# Medusa DTC Starter — Coolify Deployment Design

Date: 2026-06-14
Status: Approved

## Goal

Deploy the Medusa DTC starter monorepo (Medusa backend + Next.js storefront) to a
self-hosted Coolify server as a single Docker Compose stack. Primary immediate use
case: managing and using promotions (promo codes) via the Medusa admin and API.

## Scope

Level: **Lean** (minimum needed for a working deployment) + `.dockerignore`.

In scope:
- Production Docker images for backend and storefront (real build, not dev mode).
- Single `docker-compose.yml` stack: postgres, redis, backend, storefront.
- Fix the broken package manager configuration (pnpm restored, npm mix removed).
- Auto-migrate database on backend startup; manual seed only.

Out of scope:
- Multi-stage image optimization, healthchecks, root `.env.example` (deferred polish).
- Demo seed data on startup.
- Single-domain / path-based routing.

## Decisions

| Topic | Decision |
|-------|----------|
| What to deploy | Backend + storefront + Postgres + Redis (one compose stack). |
| Package manager | pnpm (repo is built for it; restore lockfile + workspace file). |
| Build model | One simple Dockerfile per app (single-stage). Approach 1. |
| Routing | Two subdomains via Coolify/Traefik, placeholder domains. |
| Migrations/seed | Auto `medusa db:migrate` on each start; seed is manual one-time. |

## Architecture

```
Coolify (Traefik)
  api.example.com  -> backend    :9000  (Medusa API + /app admin)
  shop.example.com -> storefront :8000  (Next.js)

internal docker network (medusa_network):
  postgres:5432   redis:6379   backend:9000   storefront:8000
```

- postgres: `postgres:15-alpine`, named volume for persistence, not exposed externally.
- redis: `redis:7-alpine`, not exposed externally.
- backend: builds from `apps/backend/Dockerfile`; entrypoint migrates then starts.
- storefront: builds from `apps/storefront/Dockerfile`; `next build` then `next start -p 8000`.

## Files

Create:
- `apps/backend/Dockerfile` — pnpm install (frozen lockfile) -> `pnpm build` -> entrypoint.
- `apps/backend/docker-entrypoint.sh` — `medusa db:migrate` then `exec medusa start`.
- `apps/storefront/Dockerfile` — pnpm install -> `next build` -> `next start -p 8000`.
- `.dockerignore` (root) — exclude `node_modules`, `.next`, `.medusa`, `.git`, `.env*`.

Modify:
- `package.json` (root) — remove npm-style `workspaces` and root `overrides`; keep clean pnpm config.
- `pnpm-workspace.yaml` — restore (`packages: [apps/*]`).
- `pnpm-lock.yaml` — regenerate via `pnpm install`.
- `docker-compose.yml` — rewrite dev->prod: 4 services, no source volume mounts, no
  `NODE_ENV=development`, each app builds from its own Dockerfile.
- `apps/backend/.env.template` — production placeholders (CORS via env, REDIS_URL, secrets).
- `apps/storefront/.env.template` — production placeholders; fix `NEXT_PUBLIC_BASE_URL`.

Do NOT create: `start.sh` / `start-storefront.sh` (those are the dev-mode scripts from the docs).

## Environment variables (placeholders, set in Coolify)

Backend:
```
DATABASE_URL=postgres://medusa:CHANGE_ME@postgres:5432/medusa
REDIS_URL=redis://redis:6379
JWT_SECRET=CHANGE_ME
COOKIE_SECRET=CHANGE_ME
STORE_CORS=https://shop.example.com
ADMIN_CORS=https://api.example.com
AUTH_CORS=https://api.example.com,https://shop.example.com
```

Storefront:
```
NEXT_PUBLIC_MEDUSA_BACKEND_URL=https://api.example.com
NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY=pk_CHANGE_ME
NEXT_PUBLIC_BASE_URL=https://shop.example.com
NEXT_PUBLIC_DEFAULT_REGION=dk
```

## Known constraint: NEXT_PUBLIC_* baked at build time

Next.js inlines `NEXT_PUBLIC_*` variables during `next build`, not at runtime. The
publishable key is created in the admin only after the backend is running. Therefore
the storefront must be (re)built after the key exists.

## Deployment order on Coolify

1. Deploy the stack. Backend migrates the DB and starts.
2. Create an admin user:
   `docker compose exec backend npx medusa user -e you@mail.com -p secret`
3. In admin (`api.example.com/app`) -> Settings -> Publishable API Keys -> copy `pk_...`.
4. Set the key in the storefront env, then rebuild only the storefront.

## Testing / verification

- Local: `docker compose up --build`.
- Backend health: `GET :9000/health` returns ok.
- Admin login works at `:9000/app`.
- Storefront loads at `:8000` and can reach the backend.
