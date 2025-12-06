const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');
require('dotenv').config();

async function main() {
  const sqlPath = path.join(__dirname, '..', 'sql', 'init.sql');
  if (!fs.existsSync(sqlPath)) {
    console.error('No se encontró', sqlPath);
    process.exit(1);
  }

  const sql = fs.readFileSync(sqlPath, 'utf8');

  const connection = await mysql.createConnection({
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT ? Number(process.env.DB_PORT) : 3306,
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    multipleStatements: true,
  });

  try {
    console.log('Ejecutando SQL de inicialización...');
    const [result] = await connection.query(sql);
    console.log('SQL ejecutado correctamente. Resultado:', Array.isArray(result) ? 'ok' : result);
    console.log('La base de datos y tablas fueron creadas/actualizadas. Si no hay errores, ya puedes correr la app.');
    process.exit(0);
  } catch (err) {
    console.error('Error ejecutando el SQL:', err.message);
    process.exit(2);
  } finally {
    try { await connection.end(); } catch(e) {}
  }
}

main();
