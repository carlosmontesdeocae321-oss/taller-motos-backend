const mysql = require('mysql2/promise');
const dotenv = require('dotenv');
dotenv.config();

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT ? Number(process.env.DB_PORT) : 3306,
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'moreira',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

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
