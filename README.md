# Medusa DTC Starter

A production-ready monorepo template for direct-to-consumer ecommerce stores powered by **Medusa 2** and **Next.js 15**. Includes a fully featured storefront with product browsing, cart, multi-step checkout, customer accounts, and a self-hosted deployment guide for **Coolify**.

[![Medusa](https://img.shields.io/badge/Medusa-2.15.5-blue)](https://docs.medusajs.com)
[![Next.js](https://img.shields.io/badge/Next.js-15.5.18-black)](https://nextjs.org)
[![pnpm](https://img.shields.io/badge/pnpm-10.11.1-orange)](https://pnpm.io)
[![Turbo](https://img.shields.io/badge/Turbo-monorepo-purple)](https://turbo.build)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

---

## What's inside

```
medusa-shop/
├── apps/
│   ├── backend/          # @dtc/backend  — Medusa 2 API (port 9000)
│   └── storefront/       # @dtc/storefront — Next.js 15 storefront (port 8000)
├── docker-compose.yml        # Production compose (Coolify / any Docker host)
├── docker-compose.dev.yml    # Local dev compose with hot-reload
├── package.json
├── pnpm-workspace.yaml
├── pnpm-lock.yaml
└── turbo.json
```

**Backend** runs Postgres 15 + Redis 7 + Medusa. It exposes the storefront API on `:9000` and the admin dashboard at `:9000/app`.

**Storefront** is a Next.js App Router frontend. It defers `next build` to container start (see [Architecture](#architecture)) so the publishable API key is always fresh.

---

## Architecture

```
Browser
  │
  │  HTTPS (public domain)
  ▼
Traefik / Coolify proxy
  ├──▶ storefront :8000   (shop.yourdomain.com)
  │        │  SSR / middleware → http://backend:9000  (Docker internal)
  │        │  Browser JS      → https://api.yourdomain.com (public HTTPS)
  └──▶ backend   :9000   (api.yourdomain.com)
           │
           ├──▶ Postgres 15
           └──▶ Redis 7
```

**Why the storefront build runs at container start, not in the Dockerfile:**

`NEXT_PUBLIC_*` variables are inlined into the JavaScript bundle at `next build` time. The publishable API key doesn't exist until the backend has booted and seeded it into Postgres. So the storefront image ships without a build; `docker-entrypoint.sh` fetches the key from Postgres, then runs `pnpm build`. A source fingerprint (`.source-stamp`) plus a persisted `.next` Docker volume means the rebuild only happens when the source or config actually changes — fast restarts, automatic redeploy on code change.

**SSR always uses the Docker-internal URL** (`http://backend:9000`). Routing SSR through the public domain would hairpin through Traefik and time out. The browser uses the public HTTPS URL (`NEXT_PUBLIC_MEDUSA_BACKEND_URL`).

---

## Quick start — Docker (local dev)

Requires Docker and Docker Compose.

```bash
git clone https://github.com/your-org/medusa-shop.git
cd medusa-shop
docker compose -f docker-compose.dev.yml up --build
```

Services:
| Service | URL |
|---|---|
| Medusa admin | http://localhost:9000/app |
| Storefront | http://localhost:8000 |
| HMR (Next.js) | ws://localhost:5173 |

The dev compose mounts source directories for hot-reload. First boot runs migrations and seeds demo data automatically.

---

## Quick start — without Docker

**Prerequisites:** Node.js v20+, PostgreSQL 15+, Redis 7+, pnpm 10+.

```bash
# 1. Install dependencies
pnpm install

# 2. Create backend .env
cp apps/backend/.env.template apps/backend/.env
# Edit apps/backend/.env — set DATABASE_URL and REDIS_URL at minimum

# 3. Migrate and seed
cd apps/backend
pnpm medusa db:migrate

# 4. Create an admin user
pnpm medusa user -e admin@example.com -p yourpassword

# 5. Start backend (http://localhost:9000)
pnpm dev

# In a second terminal — storefront setup
cd apps/storefront
cp .env.template .env.local
# Set NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY (get it from localhost:9000/app → Settings → API keys)
# Set NEXT_PUBLIC_MEDUSA_BACKEND_URL=http://localhost:9000

pnpm dev   # http://localhost:8000
```

Or run everything from the root:

```bash
pnpm dev   # starts backend + storefront via Turbo
```

---

## Environment variables

### Backend (`apps/backend/.env`)

| Variable | Required | Default | Notes |
|---|---|---|---|
| `DATABASE_URL` | Yes | — | `postgres://user:pass@host:5432/db` |
| `REDIS_URL` | Yes | — | `redis://host:6379` — must also be set in `medusa-config.ts` |
| `JWT_SECRET` | Yes | `supersecret` | **Change in production** |
| `COOKIE_SECRET` | Yes | `supersecret` | **Change in production** |
| `STORE_CORS` | Yes | — | Comma-separated storefront origins |
| `ADMIN_CORS` | Yes | — | Comma-separated admin origins |
| `AUTH_CORS` | Yes | — | Comma-separated auth origins (usually same as STORE + ADMIN) |
| `NODE_ENV` | No | `development` | Set to `production` for prod |

### Storefront (`apps/storefront/.env.local`)

| Variable | Required | Default | Notes |
|---|---|---|---|
| `NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY` | Yes | — | Fetched from Postgres automatically in Docker |
| `NEXT_PUBLIC_MEDUSA_BACKEND_URL` | Yes | `http://localhost:9000` | **Public** backend URL for browser-side calls |
| `MEDUSA_BACKEND_URL` | Prod only | `http://backend:9000` | Docker-internal URL for SSR/middleware — do not expose publicly |
| `NEXT_PUBLIC_BASE_URL` | No | `http://localhost:8000` | Public storefront URL |
| `NEXT_PUBLIC_DEFAULT_REGION` | No | `dk` | ISO-2 country code for the default region |
| `DATABASE_URL` | Prod only | — | Used by entrypoint to fetch publishable key from Postgres |
| `NEXT_PUBLIC_STRIPE_KEY` | No | — | Stripe publishable key (optional payments) |
| `NEXT_PUBLIC_MEDUSA_PAYMENTS_PUBLISHABLE_KEY` | No | — | Medusa Payments publishable key |
| `NEXT_PUBLIC_MEDUSA_PAYMENTS_ACCOUNT_ID` | No | — | Medusa Payments account ID |

> **Server vs browser:** `MEDUSA_BACKEND_URL` is read only by Next.js server-side code (middleware, RSC, SSR). It never reaches the browser. `NEXT_PUBLIC_MEDUSA_BACKEND_URL` is inlined into the client bundle and must point to the public HTTPS URL.

---

## Production deployment with Coolify

Coolify manages the Docker Compose deployment and routes traffic through its Traefik proxy. No manual port bindings or network labels needed.

### 1. Create the application

1. In Coolify, click **New Resource → Docker Compose**.
2. Connect your GitHub repository and select the `docker-compose.yml` at the repo root.
3. Choose your server and click **Save**.

### 2. Set environment variables

Add these in the Coolify **Environment Variables** tab:

```env
# Postgres
POSTGRES_DB=medusa
POSTGRES_USER=medusa
POSTGRES_PASSWORD=<strong-random-password>

# Connection strings (must match the above)
DATABASE_URL=postgres://medusa:<password>@postgres:5432/medusa
REDIS_URL=redis://redis:6379

# Secrets — generate with: openssl rand -hex 32
JWT_SECRET=<random-hex-64>
COOKIE_SECRET=<random-hex-64>

# CORS — set to your actual domains
STORE_CORS=https://shop.yourdomain.com
ADMIN_CORS=https://api.yourdomain.com
AUTH_CORS=https://shop.yourdomain.com,https://api.yourdomain.com

# Public backend URL — the browser calls this
NEXT_PUBLIC_MEDUSA_BACKEND_URL=https://api.yourdomain.com

# Storefront public URL
NEXT_PUBLIC_BASE_URL=https://shop.yourdomain.com

# Default region (ISO-2 country code)
NEXT_PUBLIC_DEFAULT_REGION=dk

# Coolify domain routing — Traefik picks these up automatically
SERVICE_FQDN_BACKEND=api.yourdomain.com
SERVICE_FQDN_STOREFRONT=shop.yourdomain.com
```

> **Do not add** `SERVICE_FQDN_POSTGRES` or `SERVICE_FQDN_REDIS` — those services should not be publicly exposed.

### 3. Deploy

Click **Deploy**. Coolify will:

1. Build the backend image (Debian `node:20`, ~3–5 min on first build).
2. Run migrations + seed (backend entrypoint).
3. Mark the backend **healthy** (healthcheck polls `/health` for up to 3 minutes).
4. Build and start the storefront — it fetches the publishable key from Postgres, then runs `next build` (~40–90 s).

**Wait for `✓ Ready` in the storefront logs before testing.** The storefront returns 504 while `next build` is running — this is expected.

### 4. Create the first admin user

```bash
docker compose exec backend sh -c \
  "cd /app/apps/backend/.medusa/server && npx medusa user -e admin@example.com -p yourpassword"
```

Then open `https://api.yourdomain.com/app`.

---

## Use this repo as a template for a new store

Click **Use this template** on GitHub to create a new repo from this one. Then follow this checklist to brand it for your store:

### Per-new-store checklist

**Secrets and config (do before first deploy):**
- [ ] Generate strong `JWT_SECRET` and `COOKIE_SECRET` — `openssl rand -hex 32`
- [ ] Set `STORE_CORS`, `ADMIN_CORS`, `AUTH_CORS` to your real domains
- [ ] Set `NEXT_PUBLIC_MEDUSA_BACKEND_URL` to your public API domain

**Seed data** (`apps/backend/src/migration-scripts/initial-data-seed.ts`):
- [ ] Store name (currently `"Default Store"`)
- [ ] Region name, countries, and currencies (currently Europe/EUR/USD covering GB, DE, DK, SE, FR, ES, IT)
- [ ] Warehouse name and address (currently `"European Warehouse"` in Copenhagen)
- [ ] Replace the 4 demo products and 4 demo categories with your actual catalog

**Storefront branding:**
- [ ] Replace `public/favicon.ico` with your icon
- [ ] Update the store name (currently `"Medusa Store"`) — hardcoded in:
  - `apps/storefront/src/app/layout.tsx` — `<title>` and `<meta name="description">`
  - `apps/storefront/src/modules/layout/templates/footer/index.tsx`
  - `apps/storefront/src/modules/layout/templates/nav/index.tsx`
  - `apps/storefront/src/modules/checkout/templates/checkout-form/index.tsx` (footer text)
  - `apps/storefront/src/app/[countryCode]/(main)/account/@login/page.tsx` (register heading)
  - Page metadata in `product`, `category`, and `account` page files
- [ ] Set `NEXT_PUBLIC_DEFAULT_REGION` to your primary country ISO-2 code

**Optional payments:**
- [ ] Add `NEXT_PUBLIC_STRIPE_KEY`, `NEXT_PUBLIC_MEDUSA_PAYMENTS_PUBLISHABLE_KEY`, `NEXT_PUBLIC_MEDUSA_PAYMENTS_ACCOUNT_ID` if using Stripe

**GitHub:**
- [ ] Enable "Template repository" in repo Settings (one-time, can't be done from code)
- [ ] Update this README with your store name and domains

---

## Troubleshooting

### 1. Backend `npm install --omit=dev` hangs silently in Docker build

**Symptom:** The build stalls for minutes with no output and eventually exits 255 at the `npm install` step.

**Cause:** `node:20-alpine` uses musl libc. Many Medusa dependencies have native addons (via `node-gyp`) with no prebuilt musl binaries, so they compile from source — which hangs in a non-TTY Docker build context.

**Fix:** The backend Dockerfile uses `FROM node:20` (Debian/glibc). Do not change it back to Alpine.

---

### 2. Build fails immediately after `pnpm install` completes (disk / overlay issue)

**Symptom:** Step 6 (pnpm install) finishes in the log, then the build exits 255 within milliseconds. No useful error message.

**Cause:** Stale or corrupted Docker build cache layers, often from prior failed builds filling the overlay filesystem. Debian images are ~1.1 GB vs Alpine's 43 MB — disk pressure hits fast on small servers.

**Fix:**

```bash
docker system prune -af   # removes stopped containers, dangling images, all build cache
```

Then redeploy. Freed ~3 GB in the case we encountered.

---

### 3. Storefront returns 504 in production (even after build finishes)

**Symptom:** Every storefront page returns 504 or hangs for ~30 s then fails.

**Cause:** The Next.js middleware (and RSC) is fetching from `NEXT_PUBLIC_MEDUSA_BACKEND_URL` (the public HTTPS domain) from inside the Docker network. This hairpins through Traefik, which cannot route the request back to the backend container — causing a 30 s timeout.

**Fix:** The storefront uses `MEDUSA_BACKEND_URL=http://backend:9000` for all server-side calls. This is set in `docker-compose.yml` and hardcoded as a production fallback in `middleware.ts` and `lib/config.ts`. Do not remove the `MEDUSA_BACKEND_URL` env var from Coolify.

---

### 4. Do not manually add the `coolify` network to services

**Symptom:** After adding `networks: coolify: external: true` to backend or storefront, the backend healthcheck never passes (stays "starting" for the full 3-minute window) and the deploy fails.

**Cause:** Coolify automatically attaches containers to its internal proxy network. Adding it manually creates a conflict that breaks internal DNS resolution and the healthcheck.

**Fix:** Remove any `coolify: external: true` network declarations from `docker-compose.yml`. The `medusa_network` bridge network is sufficient.

---

### 5. Storefront returns 504 for ~40–90 s after a fresh deploy

**Symptom:** The storefront URL returns 504 right after a deploy, even though the backend is healthy.

**Cause:** This is expected. The storefront runs `next build` at container start. The build takes 40–90 s. During this time the Next.js server is not yet listening.

**Fix:** Wait for this line in the storefront container logs:

```
✓ Ready in 596ms
```

Then the storefront is fully available.

---

### 6. Redis is ignored — Medusa uses in-memory event bus

**Symptom:** Logs show `redisUrl not found` or events don't persist across restarts.

**Cause:** Setting `REDIS_URL` as an environment variable is not enough. Medusa reads the Redis URL from `redisUrl` in `medusa-config.ts`, not directly from the environment.

**Fix:** `apps/backend/medusa-config.ts` contains `redisUrl: process.env.REDIS_URL`. Do not remove it.

---

## Useful commands

**Create an admin user:**
```bash
docker compose exec backend sh -c \
  "cd /app/apps/backend/.medusa/server && npx medusa user -e admin@example.com -p yourpassword"
```

**Read the seeded publishable key directly from Postgres:**
```bash
docker compose exec postgres psql -U medusa -d medusa -c \
  "SELECT token FROM api_key WHERE type='publishable' LIMIT 1;"
```

**Free disk space (stale Docker cache):**
```bash
docker system prune -af
```

**Tail logs for a specific service:**
```bash
docker compose logs -f backend
docker compose logs -f storefront
```

**Rebuild a single service without cache:**
```bash
docker compose build --no-cache backend
docker compose up -d backend
```

---

## Resources

- [Medusa Documentation](https://docs.medusajs.com)
- [Medusa Commerce Modules](https://docs.medusajs.com/resources/commerce-modules)
- [Next.js Documentation](https://nextjs.org/docs)
- [Coolify Documentation](https://coolify.io/docs)
- [Coolify Docker Compose guide](https://coolify.io/docs/applications/docker-compose)
