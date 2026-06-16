FROM node:20-alpine

WORKDIR /app

RUN npm install -g pnpm@10.11.1

# Install workspace dependencies (root + storefront) using the lockfile
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml turbo.json .npmrc ./
COPY apps/storefront/package.json ./apps/storefront/package.json
RUN pnpm install --frozen-lockfile --filter @dtc/storefront...

# Copy storefront source. NOTE: we deliberately do NOT run `next build` here.
# The build inlines NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY, which only exists after
# the backend has booted and seeded it. So the build is deferred to container
# start (docker-entrypoint.sh), where the key is fetched live from the database.
COPY apps/storefront ./apps/storefront
WORKDIR /app/apps/storefront

# Fingerprint the source so the entrypoint can skip rebuilding when nothing
# changed (fast restarts) and rebuild only when the code changes (auto-redeploy).
RUN find . -type f -not -path './node_modules/*' -not -path './.next/*' \
      -exec sha256sum {} + | sort | sha256sum | awk '{print $1}' > /app/.source-stamp

RUN chmod +x docker-entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["./docker-entrypoint.sh"]
