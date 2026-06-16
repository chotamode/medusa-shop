// Fetches the Medusa publishable API key directly from Postgres at container
// start. The key is created by the backend's seed during `db:migrate`, so it
// only exists after the backend has booted. We poll (rather than fail fast) to
// survive the brief race between the backend becoming healthy and the row being
// readable. Prints the token to stdout so the entrypoint can capture it.
const { Client } = require("pg")

const DATABASE_URL = process.env.DATABASE_URL
const MAX_ATTEMPTS = 60
const DELAY_MS = 2000

async function fetchKey() {
  const client = new Client({ connectionString: DATABASE_URL, ssl: false })
  try {
    await client.connect()
    const res = await client.query(
      "select token from api_key where type='publishable' limit 1"
    )
    return res.rows[0] && res.rows[0].token
  } finally {
    await client.end().catch(() => {})
  }
}

async function main() {
  if (!DATABASE_URL) {
    console.error("DATABASE_URL is not set")
    process.exit(1)
  }
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const token = await fetchKey()
      if (token) {
        process.stdout.write(token)
        return
      }
      console.error(`No publishable key yet (attempt ${attempt}/${MAX_ATTEMPTS})`)
    } catch (err) {
      console.error(`DB not ready (attempt ${attempt}/${MAX_ATTEMPTS}): ${err.message}`)
    }
    await new Promise((r) => setTimeout(r, DELAY_MS))
  }
  console.error("Publishable key not found in database after waiting")
  process.exit(1)
}

main()
