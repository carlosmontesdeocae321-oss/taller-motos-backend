const express = require('express');
const bodyParser = require('body-parser');
const fs = require('fs');
const path = require('path');
const PDFDocument = require('pdfkit');
const { pool, query, execute } = require('./db');
const morgan = require('morgan');
const cors = require('cors');
const swaggerUi = require('swagger-ui-express');
const YAML = require('yamljs');
require('dotenv').config();

const app = express();
app.use(bodyParser.json());
app.use(cors());
app.use(morgan('dev'));

const { body, param, validationResult } = require('express-validator');

function handleValidation(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    try {
      console.warn('Validation failed for', req.method, req.path, 'content-type=', req.headers['content-type']);
      try { console.warn('req.body:', JSON.stringify(req.body)); } catch (e) { console.warn('req.body: <unserializable>'); }
      try { console.warn('req.file:', req.file ? { originalname: req.file.originalname, filename: req.file.filename, size: req.file.size } : null); } catch (e) { console.warn('req.file: <error>'); }
      try { console.warn('req.files:', req.files ? Object.keys(req.files) : null); } catch (e) { console.warn('req.files: <error>'); }
      console.warn('errors=', errors.array());
    } catch (e) {}
    return res.status(400).json({ errors: errors.array() });
  }
  next();
}

const PORT = process.env.PORT || 3000;
const LOGO_PATH = process.env.LOGO_PATH || './assets/logo.png';

// Lightweight migration: ensure columns exist on servicios
async function ensureServiceColumns() {
  try {
    const haveCompleted = await query("SHOW COLUMNS FROM servicios LIKE 'completed'");
    if (!haveCompleted || haveCompleted.length === 0) {
      console.log('Adding completed column to servicios');
      await execute('ALTER TABLE servicios ADD COLUMN completed TINYINT(1) DEFAULT 0');
    }
    const haveImage = await query("SHOW COLUMNS FROM servicios LIKE 'image_path'");
    if (!haveImage || haveImage.length === 0) {
      console.log('Adding image_path column to servicios');
      await execute("ALTER TABLE servicios ADD COLUMN image_path VARCHAR(500) DEFAULT NULL");
    }
  } catch (e) {
    console.warn('Could not ensure service columns:', e.message);
  }
}

// Helper: ensure invoices directory
const INVOICES_DIR = path.join(__dirname, 'invoices');
if (!fs.existsSync(INVOICES_DIR)) fs.mkdirSync(INVOICES_DIR, { recursive: true });

// Helper: uploads directory and multer
const UPLOADS_DIR = path.join(__dirname, 'uploads');
const SERVICES_UPLOAD_DIR = path.join(UPLOADS_DIR, 'services');
if (!fs.existsSync(SERVICES_UPLOAD_DIR)) fs.mkdirSync(SERVICES_UPLOAD_DIR, { recursive: true });

// Cloudinary helper (optional)
const cloudinaryHelper = require('./lib/cloudinary');
let cloudinaryEnabled = false;
try {
  cloudinaryEnabled = cloudinaryHelper.initCloudinaryFromEnv();
  if (cloudinaryEnabled) console.log('Cloudinary enabled for image uploads');
} catch (e) {
  cloudinaryEnabled = false;
}

// Date formatting helper: returns 'Sábado YYYY-MM-DD'
function formatDateSpanish(dateInput) {
  try {
    let dateStr = null;
    if (!dateInput) return '';
    if (dateInput instanceof Date) {
      const y = dateInput.getFullYear();
      const m = (dateInput.getMonth() + 1).toString().padStart(2, '0');
      const d = dateInput.getDate().toString().padStart(2, '0');
      dateStr = `${y}-${m}-${d}`;
    } else if (typeof dateInput === 'string') {
      const s = dateInput.trim();
      // If contains ISO date
      const isoMatch = s.match(/(\d{4}-\d{2}-\d{2})/);
      if (isoMatch) {
        dateStr = isoMatch[1];
      } else {
        // Try parsing the string as a Date
        const dt = new Date(s);
        if (!isNaN(dt.getTime())) {
          const y = dt.getFullYear();
          const m = (dt.getMonth() + 1).toString().padStart(2, '0');
          const d = dt.getDate().toString().padStart(2, '0');
          dateStr = `${y}-${m}-${d}`;
        } else {
          // fallback: try to take first 10 chars (may be yyyy-mm-dd) or return original
          if (s.length >= 10) {
            dateStr = s.substring(0,10);
          } else {
            return s;
          }
        }
      }
    } else {
      return '';
    }
    const parts = dateStr.split('-').map((p) => parseInt(p, 10));
    if (parts.length !== 3) return dateStr;
    const [y, m, d] = parts;
    const dt = new Date(y, m - 1, d);
    const names = ['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'];
    const wd = names[dt.getDay()];
    return `${wd} ${dateStr}`;
  } catch (e) {
    return dateInput;
  }
}

let upload = null;
let uploadEnabled = false;
try {
  const multer = require('multer');
  const storage = multer.diskStorage({
    destination: function (req, file, cb) {
      cb(null, SERVICES_UPLOAD_DIR);
    },
    filename: function (req, file, cb) {
      const safe = Date.now() + '_' + file.originalname.replace(/[^a-zA-Z0-9.\-_]/g, '_');
      cb(null, safe);
    }
  });
  // file filter: only allow common image types
  function imageFileFilter(req, file, cb) {
    const allowed = ['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/svg+xml'];
    if (allowed.includes(file.mimetype)) cb(null, true);
    else cb(new Error('Only image files are allowed'), false);
  }
  upload = multer({ storage, limits: { fileSize: 5 * 1024 * 1024 }, fileFilter: imageFileFilter });
  uploadEnabled = true;
} catch (e) {
  console.warn('multer not installed — image upload disabled');
}

// Provide a safe middleware that no-ops when multer isn't available
const uploadMiddleware = uploadEnabled ? upload.single('image') : (req, res, next) => next();

// serve uploads statically
app.use('/uploads', express.static(UPLOADS_DIR));

// Additional upload endpoint: upload any file and return Cloudinary result (or local path)
app.post('/upload', uploadMiddleware, async (req, res) => {
  try {
    const ct = req.headers['content-type'] || '';
    if (!uploadEnabled && typeof ct === 'string' && ct.includes('multipart/form-data')) {
      return res.status(503).json({ error: 'Server is not accepting file uploads (multer not installed).' });
    }
    if (!req.file) return res.status(400).json({ error: 'No file uploaded (use field name `file`)' });
    // upload to cloudinary if configured
    if (cloudinaryEnabled && req.file && req.file.path) {
      try {
        const uploadRes = await cloudinaryHelper.uploadLocalFile(req.file.path, { folder: 'taller-motos/uploads' });
        try { fs.unlinkSync(req.file.path); } catch (er) {}
        return res.json({ ok: true, cloudinary: uploadRes });
      } catch (e) {
        console.warn('Cloudinary upload error:', e.message);
        return res.status(500).json({ error: 'Cloudinary upload failed', details: e.message });
      }
    }
    // fallback: return local path
    const localPath = `/uploads/services/${req.file.filename}`;
    res.json({ ok: true, localPath });
  } catch (err) {
    console.error('Upload error', err);
    res.status(500).json({ error: 'error handling upload' });
  }
});

// Swagger / OpenAPI
let swaggerDoc;
try {
  swaggerDoc = YAML.load(path.join(__dirname, 'openapi.yaml'));
  app.use('/docs', swaggerUi.serve, swaggerUi.setup(swaggerDoc));
} catch (e) {
  console.warn('OpenAPI doc not loaded:', e.message);
}

// --- Clients ---
app.post('/clients', [
  body('nombre').notEmpty().withMessage('nombre is required'),
  body('telefono').optional().isString(),
  body('direccion').optional().isString(),
  handleValidation,
], async (req, res) => {
  const { nombre, telefono, direccion } = req.body;
  try {
    const result = await execute('INSERT INTO clientes (nombre, telefono, direccion) VALUES (?, ?, ?)', [nombre, telefono, direccion]);
    res.json({ id_cliente: result.insertId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error inserting client' });
  }
});

app.get('/clients', async (req, res) => {
  try {
    const rows = await query('SELECT * FROM clientes ORDER BY created_at DESC');
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error fetching clients' });
  }
});

// single client CRUD
app.get('/clients/:id', [param('id').isInt().withMessage('invalid id'), handleValidation], async (req, res) => {
  const id = req.params.id;
  try {
    const rows = await query('SELECT * FROM clientes WHERE id_cliente = ?', [id]);
    if (!rows || rows.length === 0) return res.status(404).json({ error: 'client not found' });
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error fetching client' });
  }
});

app.put('/clients/:id', [
  param('id').isInt().withMessage('invalid id'),
  body('nombre').optional().isString(),
  body('telefono').optional().isString(),
  body('direccion').optional().isString(),
  handleValidation,
], async (req, res) => {
  const id = req.params.id;
  const { nombre, telefono, direccion } = req.body;
  try {
    const result = await execute('UPDATE clientes SET nombre = ?, telefono = ?, direccion = ? WHERE id_cliente = ?', [nombre, telefono, direccion, id]);
    res.json({ affectedRows: result.affectedRows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error updating client' });
  }
});

app.delete('/clients/:id', [param('id').isInt().withMessage('invalid id'), handleValidation], async (req, res) => {
  const id = req.params.id;
  try {
    const result = await execute('DELETE FROM clientes WHERE id_cliente = ?', [id]);
    res.json({ affectedRows: result.affectedRows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error deleting client' });
  }
});

// --- Motos ---
app.post('/motos', [
  body('id_cliente').isInt().withMessage('id_cliente must be an integer'),
  body('marca').notEmpty().withMessage('marca is required'),
  body('modelo').notEmpty().withMessage('modelo is required'),
  body('anio').optional().isInt().withMessage('anio must be an integer'),
  body('placa').optional().isString(),
  handleValidation,
], async (req, res) => {
  const { id_cliente, marca, modelo, anio, placa } = req.body;
  try {
    const result = await execute('INSERT INTO motos (id_cliente, marca, modelo, anio, placa) VALUES (?, ?, ?, ?, ?)', [id_cliente, marca, modelo, anio || null, placa]);
    res.json({ id_moto: result.insertId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error inserting moto' });
  }
});

// --- Moto single CRUD ---
app.get('/motos/:id', [param('id').isInt().withMessage('invalid id'), handleValidation], async (req, res) => {
  const id = req.params.id;
  try {
    const rows = await query('SELECT m.*, c.nombre as cliente_nombre FROM motos m LEFT JOIN clientes c ON m.id_cliente = c.id_cliente WHERE m.id_moto = ?', [id]);
    if (!rows || rows.length === 0) return res.status(404).json({ error: 'moto not found' });
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error fetching moto' });
  }
});

app.put('/motos/:id', [
  param('id').isInt().withMessage('invalid id'),
  body('id_cliente').optional().isInt().withMessage('id_cliente must be integer'),
  body('marca').optional().isString(),
  body('modelo').optional().isString(),
  body('anio').optional().isInt().withMessage('anio must be integer'),
  body('placa').optional().isString(),
  handleValidation,
], async (req, res) => {
  const id = req.params.id;
  const { id_cliente, marca, modelo, anio, placa } = req.body;
  try {
    const result = await execute('UPDATE motos SET id_cliente = ?, marca = ?, modelo = ?, anio = ?, placa = ? WHERE id_moto = ?', [id_cliente, marca, modelo, anio || null, placa, id]);
    res.json({ affectedRows: result.affectedRows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error updating moto' });
  }
});

app.delete('/motos/:id', [param('id').isInt().withMessage('invalid id'), handleValidation], async (req, res) => {
  const id = req.params.id;
  try {
    const result = await execute('DELETE FROM motos WHERE id_moto = ?', [id]);
    res.json({ affectedRows: result.affectedRows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error deleting moto' });
  }
});

app.get('/motos', async (req, res) => {
  try {
    const rows = await query('SELECT m.*, c.nombre as cliente_nombre FROM motos m LEFT JOIN clientes c ON m.id_cliente = c.id_cliente ORDER BY m.created_at DESC');
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error fetching motos' });
  }
});

// --- Servicios ---
// Create service with optional image upload
app.post('/services', uploadMiddleware, [
  body('id_moto').isInt().withMessage('id_moto must be integer'),
  body('descripcion').notEmpty().withMessage('descripcion is required'),
  body('fecha').isISO8601().withMessage('fecha must be a valid date (YYYY-MM-DD)'),
  body('costo').isFloat().withMessage('costo must be a number'),
  body('completed').optional().isBoolean(),
  handleValidation,
], async (req, res) => {
  // If client sent multipart/form-data but multer is not enabled, return an informative error
  try {
    const ct = req.headers['content-type'] || '';
    if (!uploadEnabled && typeof ct === 'string' && ct.includes('multipart/form-data')) {
      return res.status(503).json({ error: 'Server is not accepting file uploads (multer not installed). Install multer and restart server to enable image uploads.' });
    }
  } catch (e) {
    // ignore
  }
  const { id_moto, descripcion, fecha, costo } = req.body;
  const completed = req.body.completed ? 1 : 0;
  let imagePath = null;
    if (req.file) {
      // If Cloudinary configured, upload the local file and store the remote URL
      try {
        if (cloudinaryEnabled && req.file && req.file.path) {
          const uploadRes = await cloudinaryHelper.uploadLocalFile(req.file.path, { folder: 'taller-motos/services' });
          if (uploadRes && uploadRes.secure_url) {
            imagePath = uploadRes.secure_url;
          }
          // remove local file after upload
          try { fs.unlinkSync(req.file.path); } catch (er) {}
        } else {
          // store relative path for serving
          imagePath = `/uploads/services/${req.file.filename}`;
        }
      } catch (e) {
        console.warn('Error uploading to Cloudinary, falling back to local file:', e.message);
        imagePath = `/uploads/services/${req.file.filename}`;
      }
    }
  try {
    const result = await execute('INSERT INTO servicios (id_moto, descripcion, fecha, costo, completed, image_path) VALUES (?, ?, ?, ?, ?, ?)', [id_moto, descripcion, fecha, costo, completed, imagePath]);
    res.json({ id_servicio: result.insertId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error inserting service' });
  }
});

app.get('/services', async (req, res) => {
  try {
    const rows = await query('SELECT s.*, m.placa, m.marca, m.modelo FROM servicios s LEFT JOIN motos m ON s.id_moto = m.id_moto ORDER BY s.created_at DESC');
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error fetching services' });
  }
});

// single service CRUD
app.get('/services/:id', async (req, res) => {
  const id = req.params.id;
  try {
    const rows = await query('SELECT s.*, m.placa, m.marca, m.modelo FROM servicios s LEFT JOIN motos m ON s.id_moto = m.id_moto WHERE s.id_servicio = ?', [id]);
    if (!rows || rows.length === 0) return res.status(404).json({ error: 'service not found' });
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error fetching service' });
  }
});

app.put('/services/:id', [
  param('id').isInt().withMessage('invalid id'),
  body('id_moto').optional().isInt().withMessage('id_moto must be integer'),
  body('descripcion').optional().isString(),
  body('fecha').optional().isISO8601().withMessage('fecha must be a valid date (YYYY-MM-DD)'),
  body('costo').optional().isFloat().withMessage('costo must be a number'),
  body('completed').optional().isBoolean(),
  handleValidation,
], async (req, res) => {
  const id = req.params.id;
  const { id_moto, descripcion, fecha, costo } = req.body;
  const completed = req.body.completed !== undefined ? (req.body.completed ? 1 : 0) : null;
  try {
    const result = await execute('UPDATE servicios SET id_moto = ?, descripcion = ?, fecha = ?, costo = ?, completed = COALESCE(?, completed) WHERE id_servicio = ?', [id_moto, descripcion, fecha, costo, completed, id]);
    res.json({ affectedRows: result.affectedRows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error updating service' });
  }
});

app.delete('/services/:id', [param('id').isInt().withMessage('invalid id'), handleValidation], async (req, res) => {
  const id = req.params.id;
  try {
    const result = await execute('DELETE FROM servicios WHERE id_servicio = ?', [id]);
    res.json({ affectedRows: result.affectedRows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error deleting service' });
  }
});

// --- Facturas (PDF) ---
app.post('/invoices', [
  // Accept either: { id_servicio }, { id_moto } or { id_servicios: [1,2,3] }
  body('id_servicio').optional().isInt().withMessage('id_servicio must be integer'),
  body('id_moto').optional().isInt().withMessage('id_moto must be integer'),
  body('id_servicios').optional().isArray().withMessage('id_servicios must be an array of integers'),
  handleValidation,
], async (req, res) => {
  // body: { id_servicio } OR { id_moto } OR { id_servicios: [..] }
  const { id_servicio, id_moto, id_servicios } = req.body;
  try {
    let services = [];
    if (id_servicio) {
      services = await query('SELECT s.*, m.placa, m.marca, m.modelo, c.nombre as cliente_nombre, c.telefono, c.direccion FROM servicios s JOIN motos m ON s.id_moto = m.id_moto JOIN clientes c ON m.id_cliente = c.id_cliente WHERE s.id_servicio = ?', [id_servicio]);
    } else if (id_moto) {
      services = await query('SELECT s.*, m.placa, m.marca, m.modelo, c.nombre as cliente_nombre, c.telefono, c.direccion FROM servicios s JOIN motos m ON s.id_moto = m.id_moto JOIN clientes c ON m.id_cliente = c.id_cliente WHERE m.id_moto = ?', [id_moto]);
    } else if (Array.isArray(id_servicios) && id_servicios.length > 0) {
      const placeholders = id_servicios.map(() => '?').join(',');
      services = await query(`SELECT s.*, m.placa, m.marca, m.modelo, c.nombre as cliente_nombre, c.telefono, c.direccion FROM servicios s JOIN motos m ON s.id_moto = m.id_moto JOIN clientes c ON m.id_cliente = c.id_cliente WHERE s.id_servicio IN (${placeholders})`, id_servicios);
    } else {
      return res.status(400).json({ error: 'Provide id_servicio or id_moto or id_servicios' });
    }

    if (!services || services.length === 0) return res.status(404).json({ error: 'service(s) not found' });

    // generate single PDF that contains all services
    const invoiceId = Date.now();
    const filename = `factura_${invoiceId}.pdf`;
    const filepath = path.join(INVOICES_DIR, filename);

    const doc = new PDFDocument({ size: 'A4', margin: 50 });
    const writeStream = fs.createWriteStream(filepath);
    doc.pipe(writeStream);

    // Logo (if exists)
    if (fs.existsSync(LOGO_PATH)) {
      try { doc.image(LOGO_PATH, 50, 45, { width: 120 }); } catch (e) { console.warn('No se pudo cargar el logo:', e.message); }
    }

    // Header
    doc.fontSize(18).text('Taller de Motos Moreira Racing', 200, 50);
    const fechaHoy = new Date().toISOString().slice(0,10);
    doc.fontSize(10).text(`Fecha: ${formatDateSpanish(fechaHoy)}`, 200, 75);
    doc.moveDown(2);

    // Use first service to populate client/moto info
    const first = services[0];
    doc.fontSize(12).text('Cliente:', 50, 140);
    doc.fontSize(10).text(`${first.cliente_nombre}`, 50, 155);
    doc.text(`Teléfono: ${first.telefono || '-'}`, 50, 170);
    doc.text(`Dirección: ${first.direccion || '-'}`, 50, 185);

    doc.fontSize(12).text('Moto:', 350, 140);
    doc.fontSize(10).text(`${first.marca || '-'} ${first.modelo || '-'}`, 350, 155);
    doc.text(`Placa: ${first.placa || '-'}`, 350, 170);

    // Service table
    doc.moveDown(4);
    doc.fontSize(12).text('Detalle de servicios', 50, 220);
    doc.moveDown(0.5);

    let y = doc.y;
    doc.fontSize(10);
    let grandTotal = 0.0;
    services.forEach((s, idx) => {
      const dateOnly = (s.fecha || '').toString().split('T')[0].split(' ')[0].substring(0,10);
      const displayDate = formatDateSpanish(dateOnly);
      const costo = Number(s.costo || 0);
      grandTotal += costo;
      doc.text(`${idx+1}. ${s.descripcion}`, 50, y, { width: 350 });
      doc.text(`Fecha: ${displayDate}`, 410, y);
      y += 14;
      doc.text(`Precio: $ ${costo.toFixed(2)}`, 410, y);
      y += 20;
      if (y > 700) { doc.addPage(); y = 50; }
    });

    // Totals
    doc.moveDown(2);
    doc.fontSize(12).text('Total:', 400, y + 10);
    doc.fontSize(14).text(`$ ${grandTotal.toFixed(2)}`, 460, y + 5);

    // Footer
    doc.moveTo(50, 760).lineTo(545, 760).stroke();
    doc.fontSize(8).text('Taller de Motos Moreira Racing - Gracias por confiar en nosotros', 50, 770);

    doc.end();

    writeStream.on('finish', async () => {
      try {
        // insert a factura row per service (schema requires id_servicio not null)
        for (const s of services) {
          await execute('INSERT INTO facturas (id_servicio, fecha, total, pdf_path) VALUES (?, ?, ?, ?)', [s.id_servicio, fechaHoy, s.costo, filepath]);
        }
        res.download(filepath, filename, (err) => { if (err) console.error('Error sending file', err); });
      } catch (ie) {
        console.error('Error saving factura records', ie);
        res.status(500).json({ error: 'error saving factura records' });
      }
    });

    writeStream.on('error', (err) => { console.error('Error writing PDF', err); res.status(500).json({ error: 'error generating pdf' }); });

  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'error generating invoice' });
  }
});

// Health
app.get('/health', (req, res) => res.json({ status: 'ok' }));

// Features: report whether uploads are enabled
app.get('/features', (req, res) => {
  res.json({ uploadEnabled });
});

// Cloudinary signature endpoint (useful for client-side signed uploads)
app.get('/cloudinary-sign', (req, res) => {
  if (!cloudinaryEnabled) return res.status(503).json({ error: 'Cloudinary not configured' });
  try {
    const sig = cloudinaryHelper.generateSignature({});
    res.json(sig);
  } catch (e) {
    res.status(500).json({ error: 'Could not generate signature', details: e.message });
  }
});

// Ensure migrations then start server
ensureServiceColumns().then(() => {
  app.listen(PORT, () => {
    console.log(`Server listening on port ${PORT}`);
  });
}).catch((e) => {
  console.error('Failed running migrations:', e);
  // start server anyway
  app.listen(PORT, () => {
    console.log(`Server listening on port ${PORT} (migrations may have failed)`);
  });
});

// Central error handler (fallback)
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({ error: 'internal server error' });
});
