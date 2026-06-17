# @dtc/storefront

Next.js 15 (App Router) storefront for this monorepo. Runs on `:8000`. In production, `next build` is deferred to container start so the Medusa publishable API key can be fetched live from Postgres and inlined into the bundle.

For setup, environment variables, deployment, and troubleshooting see the [root README](../../README.md).
