const { Client } = require('pg');
const bcrypt = require('bcryptjs');
require('dotenv').config();

const candidates = [
  '123456',
  '12345678',
  '123456789',
  'password',
  'Password@123',
  'Admin@123',
  'Tirvona@123',
  'tirvona123',
  'Field@123',
  '12345'
];

async function check() {
  const client = new Client({ connectionString: process.env.SUPABASE_DB_URL });
  await client.connect();
  const res = await client.query('SELECT phone, name, password_hash FROM leads.lead_users');
  for (const row of res.rows) {
    if (!row.password_hash) continue;
    for (const p of candidates) {
      if (await bcrypt.compare(p, row.password_hash)) {
        console.log(`MATCH: ${row.phone} (${row.name}) -> Password is: "${p}"`);
        break;
      }
    }
  }
  await client.end();
}
check().catch(console.error);
