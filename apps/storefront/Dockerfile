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

# NEXT_PUBLIC_* vars are baked into the build, so they must be present at build time.
# The publishable key is created in the Medusa admin after the backend runs.
ARG NEXT_PUBLIC_MEDUSA_BACKEND_URL
ARG NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY
ARG NEXT_PUBLIC_BASE_URL
ARG NEXT_PUBLIC_DEFAULT_REGION
ENV NEXT_PUBLIC_MEDUSA_BACKEND_URL=$NEXT_PUBLIC_MEDUSA_BACKEND_URL \
    NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY=$NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY \
    NEXT_PUBLIC_BASE_URL=$NEXT_PUBLIC_BASE_URL \
    NEXT_PUBLIC_DEFAULT_REGION=$NEXT_PUBLIC_DEFAULT_REGION

RUN pnpm build

EXPOSE 8000

CMD ["pnpm", "start"]
