const { Client } = require('pg');
require('dotenv').config();

async function run() {
  const client = new Client({ connectionString: process.env.SUPABASE_DB_URL });
  await client.connect();
  const res = await client.query('SELECT phone, name, role, password_hash, created_by_admin_id FROM leads.lead_users');
  for (const r of res.rows) {
    console.log(`${r.phone} | ${r.name} (${r.role}) | hasHash: ${Boolean(r.password_hash)} | createdByAdmin: ${Boolean(r.created_by_admin_id)}`);
  }
  await client.end();
}

run().catch(console.error);
