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
