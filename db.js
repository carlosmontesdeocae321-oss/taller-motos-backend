const mysql = require('mysql2/promise');
const dotenv = require('dotenv');
const fs = require('fs');
dotenv.config();

// Support for both our DB_* env vars and Railway-provided MYSQL* vars.
// Also parse MYSQL_URL if provided (format: mysql://user:pass@host:port/dbname).
let host = 'localhost';
let port = 3306;
let user = 'root';
let password = '';
let database = 'moreira';

// If a full URL is provided, parse it first (takes precedence but
// individual env vars can still override the parsed values).
if (process.env.MYSQL_URL) {
  try {
    const parsed = new URL(process.env.MYSQL_URL);
    if (parsed.protocol && parsed.protocol.startsWith('mysql')) {
      if (parsed.hostname) host = parsed.hostname;
      if (parsed.port) port = Number(parsed.port);
      if (parsed.username) user = parsed.username;
      if (parsed.password) password = parsed.password;
      if (parsed.pathname && parsed.pathname.length > 1) database = parsed.pathname.replace(/^\//, '');
    }
  } catch (e) {
    console.warn('Could not parse MYSQL_URL:', e.message);
  }
}

// Allow explicit individual env vars to override the parsed/ default values.
host = process.env.DB_HOST || process.env.MYSQLHOST || host;
port = process.env.DB_PORT ? Number(process.env.DB_PORT) : (process.env.MYSQLPORT ? Number(process.env.MYSQLPORT) : port);
user = process.env.DB_USER || process.env.MYSQLUSER || user;
password = process.env.DB_PASSWORD || process.env.MYSQLPASSWORD || password;
database = process.env.DB_NAME || process.env.MYSQLDATABASE || database;

// Build pool options and optionally enable SSL when requested by env vars
const poolOptions = {
  host,
  port,
  user,
  password,
  database,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
};

// Enable SSL when set (useful for managed DB providers that require TLS)
if (process.env.MYSQL_SSL === 'true' || process.env.DB_SSL === 'true') {
  poolOptions.ssl = {
    // By default reject unauthorized; set MYSQL_SSL_REJECT_UNAUTHORIZED=false to allow self-signed certs
    rejectUnauthorized: process.env.MYSQL_SSL_REJECT_UNAUTHORIZED !== 'false'
  };
  // If a CA path is provided, attach it
  if (process.env.MYSQL_SSL_CA_PATH) {
    try {
      poolOptions.ssl.ca = fs.readFileSync(process.env.MYSQL_SSL_CA_PATH, 'utf8');
    } catch (e) {
      console.warn('Could not read MYSQL_SSL_CA_PATH:', e.message);
    }
  }
}

const pool = mysql.createPool(poolOptions);

// Attempt an initial connection to surface early errors in logs
async function testConnection() {
  try {
    const conn = await pool.getConnection();
    try { await conn.ping(); } catch (e) {}
    conn.release();
    console.log(`MySQL: connected to ${host}:${port}/${database} as ${user}`);
  } catch (e) {
    console.error('MySQL connection error:', e.message || e);
  }
}

// Run test asynchronously (don't block module export)
testConnection();

module.exports = {
  pool,
  query: async (sql, params) => {
    const [rows] = await pool.execute(sql, params);
    return rows;
  },
  // execute: use when you need the result object (insertId, affectedRows, etc.)
  execute: async (sql, params) => {
    const [result] = await pool.execute(sql, params);
    return result;
  }
};
