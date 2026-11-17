const { Client } = require('pg');
const bcrypt = require('bcryptjs');
require('dotenv').config();

async function run() {
  const hash = await bcrypt.hash('12345678', 10);
  const client = new Client({ connectionString: process.env.SUPABASE_DB_URL });
  await client.connect();
  
  // Set password for 1234567891, 8630949349, 1234567899
  const res = await client.query(
    'UPDATE leads.lead_users SET password_hash = $1 WHERE phone IN ($2, $3, $4) RETURNING phone, name, role',
    [hash, '1234567891', '8630949349', '1234567899']
  );
  console.log('Updated passwords for:', res.rows);
  await client.end();
}

run().catch(console.error);
