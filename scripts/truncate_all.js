#!/usr/bin/env node
const { query, execute } = require('../db');

async function showCounts() {
  const tables = ['facturas','servicios','motos','clientes'];
  console.log('Checking row counts for tables: ', tables.join(', '));
  for (const t of tables) {
    try {
      const rows = await query(`SELECT COUNT(*) AS c FROM ${t}`);
      const c = rows && rows[0] ? rows[0].c : 0;
      console.log(`${t}: ${c}`);
    } catch (e) {
      console.error(`Error querying ${t}:`, e.message || e);
    }
  }
}

async function doTruncate() {
  const tables = ['facturas','servicios','motos','clientes'];
  try {
    console.log('Disabling foreign key checks');
    await execute('SET FOREIGN_KEY_CHECKS = 0');
    for (const t of tables) {
      try {
        console.log(`Truncating ${t}...`);
        await execute(`TRUNCATE TABLE ${t}`);
        console.log(`${t} truncated`);
      } catch (e) {
        console.error(`Failed truncating ${t}:`, e.message || e);
      }
    }
    console.log('Re-enabling foreign key checks');
    await execute('SET FOREIGN_KEY_CHECKS = 1');
    console.log('Truncate completed');
  } catch (e) {
    console.error('Truncate process failed:', e.message || e);
  }
}

async function main() {
  await showCounts();
  if (process.argv.includes('--doit')) {
    console.log('\n--doit flag present: performing truncates');
    await doTruncate();
    console.log('\nFinal counts after truncate:');
    await showCounts();
  } else {
    console.log('\nRun with --doit to actually perform truncates');
  }
  process.exit(0);
}

main().catch((e)=>{ console.error(e); process.exit(1); });
