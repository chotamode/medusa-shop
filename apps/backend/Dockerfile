FROM node:20

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
RUN npm install --omit=dev --no-audit --no-fund

# Entrypoint runs migrations then starts the server
COPY apps/backend/docker-entrypoint.sh /app/apps/backend/docker-entrypoint.sh
RUN chmod +x /app/apps/backend/docker-entrypoint.sh

EXPOSE 9000

ENTRYPOINT ["/app/apps/backend/docker-entrypoint.sh"]
