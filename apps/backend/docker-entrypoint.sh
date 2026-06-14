#!/bin/sh
set -e

cd /app/apps/backend/.medusa/server

echo "Running database migrations..."
npm run predeploy

echo "Starting Medusa server..."
exec npm run start
