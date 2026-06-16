#!/bin/sh
# Runtime build + start for the storefront.
#
# Why build here instead of in the Dockerfile? Next.js inlines NEXT_PUBLIC_*
# into the JS bundle at `next build` time. The publishable key only exists after
# the backend has booted and seeded it, so we cannot bake it into the image.
# Instead we fetch the key from the database at container start, then build.
#
# To stay fast on restarts and robust across auto-redeploys, we only rebuild when
# the source (fingerprinted at image build) or the public config actually
# changed. The fingerprint is stored in the persisted .next volume.
set -e

cd /app/apps/storefront

echo "Fetching publishable key from database..."
NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY="$(node get-publishable-key.js)"
export NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY
echo "Got publishable key (length ${#NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY})."

# Build signature = source fingerprint (baked into the image) + every public var
# that gets inlined into the bundle. Any change invalidates the cached build.
WANT="$(cat /app/.source-stamp)|${NEXT_PUBLIC_MEDUSA_BACKEND_URL}|${NEXT_PUBLIC_MEDUSA_PUBLISHABLE_KEY}|${NEXT_PUBLIC_BASE_URL}|${NEXT_PUBLIC_DEFAULT_REGION}"
WANT_HASH="$(printf '%s' "$WANT" | sha256sum | awk '{print $1}')"
STAMP=".next/.build-stamp"

if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$WANT_HASH" ]; then
  echo "Source or config changed - building storefront..."
  pnpm build
  # next build wipes .next, so write the stamp afterwards.
  printf '%s' "$WANT_HASH" > "$STAMP"
else
  echo "No changes - reusing cached build."
fi

echo "Starting storefront..."
exec pnpm start
