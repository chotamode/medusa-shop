# Medusa Coolify Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Medusa DTC starter monorepo deployable to Coolify as a single Docker Compose stack (postgres + redis + backend + storefront) with production builds.

**Architecture:** One simple single-stage Dockerfile per app. Backend builds with `medusa build` (output in `.medusa/server`) and starts via an entrypoint that runs migrations then `medusa start`. Storefront builds with `next build` and runs `next start`. A rewritten `docker-compose.yml` wires all four services on an internal network; only backend and storefront are exposed (via Coolify/Traefik). Package manager is pnpm.

**Tech Stack:** Medusa v2.15.5, Next.js 15, pnpm 10.11.1, Node 20-alpine, PostgreSQL 15, Redis 7, Docker Compose.

**Note on verification:** This is infrastructure config — there are no unit tests. "Verification" steps use `docker compose config`, `docker build`, and `curl` against a locally running stack. Commit after each task.

---

### Task 1: Fix package manager configuration (pnpm)

The root `package.json` currently mixes pnpm and npm config, and the pnpm workspace/lock files were deleted. Restore a clean pnpm setup.

**Files:**
- Modify: `package.json`
- Create: `pnpm-workspace.yaml`
- Regenerate: `pnpm-lock.yaml`

- [ ] **Step 1: Restore `pnpm-workspace.yaml`**

Create `pnpm-workspace.yaml`:

```yaml
packages:
  - "apps/*"
```

- [ ] **Step 2: Clean root `package.json`**

Replace the file with the pnpm-only version (removes npm-style `workspaces` and the duplicate root `overrides`, keeps the `pnpm.overrides`):

```json
{
  "name": "dtc-starter-monorepo",
  "private": false,
  "packageManager": "pnpm@10.11.1",
  "engines": {
    "node": ">=20"
  },
  "scripts": {
    "dev": "pnpm -r dev",
    "build": "pnpm -r build",
    "start": "turbo start",
    "lint": "turbo lint",
    "test": "turbo test",
    "backend:seed": "turbo seed --filter=@dtc/backend",
    "backend:dev": "turbo dev --filter=@dtc/backend",
    "storefront:dev": "turbo dev --filter=@dtc/storefront"
  },
  "pnpm": {
    "overrides": {
      "@types/react": "19.0.5",
      "@types/react-dom": "19.0.5"
    }
  },
  "devDependencies": {
    "turbo": "^2.0.14",
    "prettier": "^3.2.5"
  }
}
```

- [ ] **Step 3: Regenerate the lockfile**

Run: `pnpm install`
Expected: completes, recreates `pnpm-lock.yaml`, installs into `node_modules`.

- [ ] **Step 4: Verify workspaces resolve**

Run: `pnpm -r exec node -e "console.log(require('./package.json').name)"`
Expected: prints `@dtc/backend` and `@dtc/storefront`.

- [ ] **Step 5: Commit**

```bash
git add package.json pnpm-workspace.yaml pnpm-lock.yaml
git commit -m "fix: restore clean pnpm workspace configuration"
```

---

### Task 2: Add root `.dockerignore`

Prevents Docker from sending `node_modules`, build artifacts, and secrets into the build context.

**Files:**
- Create: `.dockerignore`

- [ ] **Step 1: Create `.dockerignore`**

```
node_modules
**/node_modules
apps/backend/.medusa
apps/storefront/.next
.git
.gitignore
.github
**/.env
**/.env.*
!**/.env.template
*.log
npm-debug.log*
.DS_Store
docs
README.md
LICENSE
```

- [ ] **Step 2: Commit**

```bash
git add .dockerignore
git commit -m "chore: add root .dockerignore for docker builds"
```

---

### Task 3: Backend production Dockerfile and entrypoint

Build the Medusa app with `medusa build` (outputs `.medusa/server`), then run from that output. The entrypoint runs migrations (`predeploy`) then starts the server.

**Files:**
- Modify: `apps/backend/package.json` (add `predeploy` script)
- Create: `apps/backend/docker-entrypoint.sh`
- Create: `apps/backend/Dockerfile`

- [ ] **Step 1: Add `predeploy` script to `apps/backend/package.json`**

In the `"scripts"` object, add this entry (keep all existing scripts):

```json
"predeploy": "medusa db:migrate"
```

The scripts block becomes:

```json
  "scripts": {
    "build": "medusa build",
    "start": "medusa start",
    "dev": "medusa develop",
    "predeploy": "medusa db:migrate",
    "test:integration:http": "TEST_TYPE=integration:http NODE_OPTIONS=--experimental-vm-modules jest --silent=false --runInBand --forceExit",
    "test:integration:modules": "TEST_TYPE=integration:modules NODE_OPTIONS=--experimental-vm-modules jest --silent=false --runInBand --forceExit",
    "test:unit": "TEST_TYPE=unit NODE_OPTIONS=--experimental-vm-modules jest --silent --runInBand --forceExit"
  },
```

- [ ] **Step 2: Create `apps/backend/docker-entrypoint.sh`**

```sh
#!/bin/sh
set -e

cd /app/apps/backend/.medusa/server

echo "Running database migrations..."
npm run predeploy

echo "Starting Medusa server..."
exec npm run start
```

- [ ] **Step 3: Create `apps/backend/Dockerfile`**

```dockerfile
FROM node:20-alpine

WORKDIR /app

RUN npm install -g pnpm@10.11.1

# Install workspace dependencies (root + backend) using the lockfile
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml turbo.json .npmrc ./
COPY apps/backend/package.json ./apps/backend/package.json
RUN pnpm install --frozen-lockfile --filter @dtc/backend...

# Copy backend source and build (outputs to apps/backend/.medusa/server)
COPY apps/backend ./apps/backend
WORKDIR /app/apps/backend
RUN pnpm build

# Install production dependencies inside the build output
WORKDIR /app/apps/backend/.medusa/server
RUN npm install --omit=dev

# Entrypoint runs migrations then starts the server
COPY apps/backend/docker-entrypoint.sh /app/apps/backend/docker-entrypoint.sh
RUN chmod +x /app/apps/backend/docker-entrypoint.sh

EXPOSE 9000

ENTRYPOINT ["/app/apps/backend/docker-entrypoint.sh"]
```

- [ ] **Step 4: Verify the backend image builds**

Run: `docker build -f apps/backend/Dockerfile -t medusa-backend-test .`
Expected: build succeeds; final image created. If `pnpm build` fails on missing env, that is expected to be fine (build does not need DB). If `.medusa/server` is missing after build, stop and inspect the build logs.

- [ ] **Step 5: Commit**

```bash
git add apps/backend/package.json apps/backend/docker-entrypoint.sh apps/backend/Dockerfile
git commit -m "feat: add backend production Dockerfile and migrate-on-start entrypoint"
```

---

### Task 4: Storefront production Dockerfile

Build the Next.js storefront and run it with `next start` on port 8000.

**Files:**
- Create: `apps/storefront/Dockerfile`

- [ ] **Step 1: Create `apps/storefront/Dockerfile`**

```dockerfile
FROM node:20-alpine

WORKDIR /app

RUN npm install -g pnpm@10.11.1

# Install workspace dependencies (root + storefront) using the lockfile
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml turbo.json .npmrc ./
COPY apps/storefront/package.json ./apps/storefront/package.json
RUN pnpm install --frozen-lockfile --filter @dtc/storefront...

# Copy storefront source and build
COPY apps/storefront ./apps/storefront
WORKDIR /app/apps/storefront
RUN pnpm build

EXPOSE 8000

CMD ["pnpm", "start"]
```

- [ ] **Step 2: Verify the storefront image builds**

Run: `docker build -f apps/storefront/Dockerfile -t medusa-storefront-test .`
Expected: build succeeds. Note: `next build` reads `NEXT_PUBLIC_*` vars; for a bare build test, the storefront's `check-env-variables.js` may warn about a missing publishable key — that is acceptable for this build-only check. If the build hard-fails on the missing key, set a dummy `NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY=pk_test` build arg/env and re-run; this will be supplied for real in Task 5/deployment.

- [ ] **Step 3: Commit**

```bash
git add apps/storefront/Dockerfile
git commit -m "feat: add storefront production Dockerfile"
```

---

### Task 5: Rewrite `docker-compose.yml` for production

Replace the dev-oriented compose (volume-mounted source, `pnpm dev`) with a production stack that builds each app from its Dockerfile.

**Files:**
- Modify: `docker-compose.yml`

- [ ] **Step 1: Replace `docker-compose.yml`**

```yaml
services:
  postgres:
    image: postgres:15-alpine
    container_name: medusa_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-medusa}
      POSTGRES_USER: ${POSTGRES_USER:-medusa}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-medusa}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - medusa_network

  redis:
    image: redis:7-alpine
    container_name: medusa_redis
    restart: unless-stopped
    networks:
      - medusa_network

  backend:
    build:
      context: .
      dockerfile: apps/backend/Dockerfile
    container_name: medusa_backend
    restart: unless-stopped
    depends_on:
      - postgres
      - redis
    environment:
      - NODE_ENV=production
      - DATABASE_URL=${DATABASE_URL:-postgres://medusa:medusa@postgres:5432/medusa}
      - REDIS_URL=${REDIS_URL:-redis://redis:6379}
      - JWT_SECRET=${JWT_SECRET:-supersecret}
      - COOKIE_SECRET=${COOKIE_SECRET:-supersecret}
      - STORE_CORS=${STORE_CORS:-http://localhost:8000}
      - ADMIN_CORS=${ADMIN_CORS:-http://localhost:9000}
      - AUTH_CORS=${AUTH_CORS:-http://localhost:8000,http://localhost:9000}
    ports:
      - "9000:9000"
    networks:
      - medusa_network

  storefront:
    build:
      context: .
      dockerfile: apps/storefront/Dockerfile
    container_name: medusa_storefront
    restart: unless-stopped
    depends_on:
      - backend
    environment:
      - NODE_ENV=production
      - NEXT_PUBLIC_MEDUSA_BACKEND_URL=${NEXT_PUBLIC_MEDUSA_BACKEND_URL:-http://localhost:9000}
      - NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY=${NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY:-}
      - NEXT_PUBLIC_BASE_URL=${NEXT_PUBLIC_BASE_URL:-http://localhost:8000}
      - NEXT_PUBLIC_DEFAULT_REGION=${NEXT_PUBLIC_DEFAULT_REGION:-dk}
    ports:
      - "8000:8000"
    networks:
      - medusa_network

volumes:
  postgres_data:

networks:
  medusa_network:
    driver: bridge
```

- [ ] **Step 2: Validate the compose file**

Run: `docker compose config`
Expected: prints the resolved configuration with no errors.

- [ ] **Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: rewrite docker-compose for production deployment"
```

---

### Task 6: Update env templates

Document production variables with placeholders so they can be set in Coolify.

**Files:**
- Modify: `apps/backend/.env.template`
- Modify: `apps/storefront/.env.template`

- [ ] **Step 1: Replace `apps/backend/.env.template`**

```
# Database (inside the compose network the host is `postgres`)
DATABASE_URL=postgres://medusa:CHANGE_ME@postgres:5432/medusa

# Redis (inside the compose network the host is `redis`)
REDIS_URL=redis://redis:6379

# Secrets - generate strong random values for production
JWT_SECRET=CHANGE_ME
COOKIE_SECRET=CHANGE_ME

# CORS - set to your real domains in Coolify
STORE_CORS=https://shop.example.com
ADMIN_CORS=https://api.example.com
AUTH_CORS=https://api.example.com,https://shop.example.com
```

- [ ] **Step 2: Replace `apps/storefront/.env.template`**

```
# Publishable API key - create it in the admin after backend is running,
# then set it here and rebuild the storefront (NEXT_PUBLIC_* is baked at build time).
NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY=pk_CHANGE_ME

# Public URL of the Medusa backend
NEXT_PUBLIC_MEDUSA_BACKEND_URL=https://api.example.com

# Public URL of the storefront itself
NEXT_PUBLIC_BASE_URL=https://shop.example.com

# Default region code
NEXT_PUBLIC_DEFAULT_REGION=dk
```

- [ ] **Step 3: Commit**

```bash
git add apps/backend/.env.template apps/storefront/.env.template
git commit -m "docs: update env templates with production placeholders"
```

---

### Task 7: End-to-end local verification

Bring the whole stack up locally to confirm it works before deploying to Coolify.

**Files:** none (verification only)

- [ ] **Step 1: Build and start the stack**

Run: `docker compose up --build -d`
Expected: postgres, redis, backend, storefront containers start. Backend may take a minute (runs migrations on first start).

- [ ] **Step 2: Check backend health**

Run: `curl -f http://localhost:9000/health`
Expected: HTTP 200 (the endpoint returns `OK`).

- [ ] **Step 3: Confirm admin assets load**

Run: `curl -fsI http://localhost:9000/app | head -n 1`
Expected: `HTTP/1.1 200 OK` (admin dashboard HTML is served).

- [ ] **Step 4: Create an admin user**

Run: `docker compose exec backend sh -c "cd /app/apps/backend/.medusa/server && npx medusa user -e admin@example.com -p supersecret"`
Expected: confirms the user was created.

- [ ] **Step 5: Confirm storefront responds**

Run: `curl -fsI http://localhost:8000 | head -n 1`
Expected: `HTTP/1.1 200 OK` (storefront may show errors about the publishable key until one is set — that is expected and handled in the deployment order).

- [ ] **Step 6: Tear down**

Run: `docker compose down`
Expected: containers removed (the `postgres_data` volume persists).

- [ ] **Step 7: Commit any fixes**

If Steps 1-5 required adjustments to Dockerfiles or compose, commit them:

```bash
git add -A
git commit -m "fix: adjustments from local stack verification"
```

---

## Coolify deployment notes (post-implementation, manual)

1. In Coolify, create a **Docker Compose** resource pointing at this repo; it uses `docker-compose.yml`.
2. Set the env variables (from the templates) in Coolify with real domains and strong secrets.
3. Attach domains: `api.example.com` -> backend (port 9000), `shop.example.com` -> storefront (port 8000).
4. Deploy. Backend migrates and starts.
5. Create admin user (Step 4 above, via Coolify terminal).
6. In admin -> Settings -> Publishable API Keys, copy `pk_...`, set `NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY`, redeploy storefront.

---

## Self-Review Notes

- Spec coverage: pnpm fix (Task 1), .dockerignore (Task 2), backend Dockerfile+entrypoint+migrate (Task 3), storefront Dockerfile (Task 4), compose rewrite (Task 5), env templates (Task 6), verification + deploy order (Task 7 + notes). All spec items covered.
- The `predeploy` script (Task 3) is the migrate-on-start mechanism the spec's "auto-migrate" decision requires.
- The `NEXT_PUBLIC_*` build-time constraint is handled via the deployment order notes.
