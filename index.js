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
    // Ensure descripcion column can hold long text (change to TEXT if currently shorter)
    try {
      const descCol = await query("SHOW COLUMNS FROM servicios LIKE 'descripcion'");
      if (descCol && descCol[0] && descCol[0].Type) {
        const type = ('' + descCol[0].Type).toLowerCase();
        if (!type.includes('text')) {
          console.log('Altering servicios.descripcion to TEXT to allow long descriptions');
          await execute("ALTER TABLE servicios MODIFY COLUMN descripcion TEXT NOT NULL");
        }
      }
    } catch (e) {
      console.warn('Could not ensure descripcion column type:', e && e.message ? e.message : e);
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

app.put('/services/:id', uploadMiddleware, [
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
    // handle image updates: detect whether client explicitly provided `image_path`
    // If the client sent `image_path` (even as empty string), treat that as an explicit request
    // to set/clear the field. If not provided, image updates from uploaded file will be appended.
    let imagePathProvided = false;
    let imagePathValue = undefined; // undefined means "not provided"
    if (Object.prototype.hasOwnProperty.call(req.body, 'image_path')) {
      imagePathProvided = true;
      // empty string -> clear (null), otherwise keep the provided value
      imagePathValue = (req.body.image_path === '' ? null : req.body.image_path);
    }

    // If a file was uploaded, process it: upload to cloudinary if configured, else store local path
    // The result will be placed in `uploadedImagePath` (undefined if none)
    let uploadedImagePath = undefined;
    if (req.file) {
      try {
        let newImg = null;
        if (cloudinaryEnabled && req.file && req.file.path) {
          const uploadRes = await cloudinaryHelper.uploadLocalFile(req.file.path, { folder: 'taller-motos/services' });
          if (uploadRes && uploadRes.secure_url) newImg = uploadRes.secure_url;
          try { fs.unlinkSync(req.file.path); } catch (er) {}
        } else {
          newImg = `/uploads/services/${req.file.filename}`;
        }

        if (newImg) {
          if (imagePathProvided) {
            // client explicitly provided a base value for image_path — honor it and append new image if base is non-empty
            if (imagePathValue && imagePathValue.length > 0) uploadedImagePath = imagePathValue + ',' + newImg;
            else uploadedImagePath = newImg;
          } else {
            // no explicit instruction: fetch existing and append
            try {
              const rows = await query('SELECT image_path FROM servicios WHERE id_servicio = ?', [id]);
              const existing = (rows && rows[0] && rows[0].image_path) ? rows[0].image_path : null;
              uploadedImagePath = existing ? existing + ',' + newImg : newImg;
            } catch (ee) {
              uploadedImagePath = newImg;
            }
          }
        }
      } catch (e) {
        console.warn('Error processing uploaded file for update:', e && e.message ? e.message : e);
      }
    }

    // Build update query. Use COALESCE for optional fields and ensure we don't pass `undefined` to the driver.
    const idMotoParam = (typeof id_moto !== 'undefined') ? id_moto : null;
    const descripcionParam = (typeof descripcion !== 'undefined') ? descripcion : null;
    const fechaParam = (typeof fecha !== 'undefined') ? fecha : null;
    const costoParam = (typeof costo !== 'undefined') ? costo : null;
    const completedParam = (typeof completed !== 'undefined') ? completed : null;

    // Determine final image parameter:
    // If client explicitly provided image_path, honor that (may be null to clear), but if an uploadedImagePath exists prefer it.
    let finalImageParam = undefined;
    if (imagePathProvided) {
      finalImageParam = (typeof uploadedImagePath !== 'undefined') ? uploadedImagePath : imagePathValue;
    } else {
      if (typeof uploadedImagePath !== 'undefined') finalImageParam = uploadedImagePath;
    }

    if (imagePathProvided) {
      // explicit set/clear: set image_path to finalImageParam (can be null)
      const sql = `UPDATE servicios SET id_moto = COALESCE(?, id_moto), descripcion = COALESCE(?, descripcion), fecha = COALESCE(?, fecha), costo = COALESCE(?, costo), completed = COALESCE(?, completed), image_path = ? WHERE id_servicio = ?`;
      const result = await execute(sql, [idMotoParam, descripcionParam, fechaParam, costoParam, completedParam, finalImageParam, id]);
      res.json({ affectedRows: result.affectedRows });
    } else if (typeof finalImageParam !== 'undefined') {
      // we have a new uploaded image and client didn't explicitly touch image_path -> set/append
      const sql = `UPDATE servicios SET id_moto = COALESCE(?, id_moto), descripcion = COALESCE(?, descripcion), fecha = COALESCE(?, fecha), costo = COALESCE(?, costo), completed = COALESCE(?, completed), image_path = COALESCE(?, image_path) WHERE id_servicio = ?`;
      const result = await execute(sql, [idMotoParam, descripcionParam, fechaParam, costoParam, completedParam, finalImageParam, id]);
      res.json({ affectedRows: result.affectedRows });
    } else {
      // don't touch image_path
      const sql = `UPDATE servicios SET id_moto = COALESCE(?, id_moto), descripcion = COALESCE(?, descripcion), fecha = COALESCE(?, fecha), costo = COALESCE(?, costo), completed = COALESCE(?, completed) WHERE id_servicio = ?`;
      const result = await execute(sql, [idMotoParam, descripcionParam, fechaParam, costoParam, completedParam, id]);
      res.json({ affectedRows: result.affectedRows });
    }
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
  console.log('POST /invoices called with body:', JSON.stringify(req.body));
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

    console.log('Found services for invoice:', services && services.length);
    if (!services || services.length === 0) return res.status(404).json({ error: 'service(s) not found' });

    // helper: fetch remote image into a buffer (kept for potential future thumbnails)
    function fetchImageBuffer(url) {
      return new Promise((resolve, reject) => {
        try {
          const client = url.startsWith('https') ? require('https') : require('http');
          client.get(url, (resp) => {
            const chunks = [];
            resp.on('data', (chunk) => chunks.push(chunk));
            resp.on('end', () => resolve(Buffer.concat(chunks)));
          }).on('error', (err) => reject(err));
        } catch (e) { reject(e); }
      });
    }

    // generate single PDF that matches factura_13 layout
    function nextHistFilename() {
      try {
        const files = fs.readdirSync(INVOICES_DIR);
        // prefer 'historial.pdf' if available
        if (!files.includes('historial.pdf')) return 'historial.pdf';
        let i = 1;
        while (files.includes(`historial${i}.pdf`)) i++;
        return `historial${i}.pdf`;
      } catch (e) {
        // fallback to timestamped name if invoices dir unreadable
        return `historial_${Date.now()}.pdf`;
      }
    }
    const filename = nextHistFilename();
    const filepath = path.join(INVOICES_DIR, filename);

    const doc = new PDFDocument({ size: 'A4', margin: 50, bufferPages: true });
    const writeStream = fs.createWriteStream(filepath);
    doc.pipe(writeStream);

    const fechaHoy = new Date().toISOString().slice(0,10);

    // Logo area with gray background
    if (fs.existsSync(LOGO_PATH)) {
      try {
        doc.save();
        doc.rect(50, 45, 120, 72).fill('#dddddd');
        doc.image(LOGO_PATH, 60, 55, { width: 100 });
        doc.restore();
      } catch (e) { console.warn('Logo draw failed:', e.message); }
    }

    // Title and metadata to the right of logo
    doc.font('Helvetica-Bold').fontSize(20).fillColor('#000').text('Taller de Motos Moreira Racing', 190, 55);
    doc.font('Helvetica').fontSize(10).fillColor('#000').text(`Fecha: ${formatDateSpanish(fechaHoy)}`, 190, 80);

    // thin divider
    doc.moveTo(50, 125).lineTo(545, 125).strokeColor('#eeeeee').stroke();

    // client / moto columns (no heavy boxed borders — match factura_13)
    const first = services[0];
    doc.font('Helvetica-Bold').fontSize(11).text('Cliente:', 50, 135);
    doc.font('Helvetica').fontSize(10).text(`${first.cliente_nombre || '-'}`, 50, 152);
    doc.font('Helvetica').fontSize(9).fillColor('#555').text(`Teléfono: ${first.telefono || '-'}`, 50, 168);
    doc.font('Helvetica').fontSize(9).fillColor('#555').text(`Dirección: ${first.direccion || '-'}`, 50, 182);

    doc.font('Helvetica-Bold').fontSize(11).fillColor('#000').text('Moto:', 360, 135);
    doc.font('Helvetica').fontSize(10).text(`${first.marca || '-'} ${first.modelo || '-'}`, 360, 152);
    doc.font('Helvetica').fontSize(9).fillColor('#555').text(`Placa: ${first.placa || '-'}`, 360, 168);

    // Services: simple list with date (short) and price on the right — no thumbnails
    let y = 220;
    doc.font('Helvetica-Bold').fontSize(12).fillColor('#000').text('Detalle de servicios', 50, y - 14);
    let grandTotal = 0.0;
    for (let idx = 0; idx < services.length; idx++) {
      const s = services[idx];
      const costo = Number(s.costo || 0);
      grandTotal += costo;

      const dateOnly = (s.fecha || '').toString().split('T')[0].split(' ')[0].substring(0,10);
      const displayDate = formatDateSpanish(dateOnly);

      // Collect images list for this service. Description is shown as text only;
      // images will be rendered below the price in a grid (two per row).
      let imgs = [];
      try {
        if (s.image_path) imgs = ('' + s.image_path).split(',').map(p => p.trim()).filter(Boolean);
      } catch (ie) { console.warn('Image list parse error for service', s.id_servicio, ie && ie.message ? ie.message : ie); }

      // Description: full text only (no inline thumbnails)
      const textX = 50;
      const descWidth = 360;
      doc.font('Helvetica').fontSize(10).fillColor('#000').text(`${idx+1}. ${s.descripcion || '-'}`, textX, y, { width: descWidth });
      // Date and price to the right
      doc.font('Helvetica').fontSize(9).fillColor('#444').text(`Fecha: ${displayDate}`, 420, y);
      doc.font('Helvetica').fontSize(10).fillColor('#000').text(`Precio: $ ${costo.toFixed(2)}`, 420, y + 14);

      // advance Y after description/price
      y += 34;
      // Only add a new page if there are more services to render. This avoids
      // creating a trailing blank page when the last service exactly overflows
      // the current page boundary.
      if (y > 700 && idx < services.length - 1) {
        doc.addPage();
        y = 50;
      }
      // Render images (if any) below the price in a grid: 2 images per row
      try {
        if (imgs && imgs.length > 0) {
          const imgDisplayWidth = 240;
          const imgDisplayHeight = 140;
          const perRow = 2;
          const marginLeft = 50;
          const spacing = 20;
          let col = 0;
          let drawnAny = false;
          for (const imgPath of imgs) {
            let buf2 = null;
            if (imgPath.startsWith('http://') || imgPath.startsWith('https://')) {
              try { buf2 = await fetchImageBuffer(imgPath); } catch (e) { console.warn('Fetch image failed', e && e.message ? e.message : e); }
            } else {
              const local2 = path.join(__dirname, imgPath.startsWith('/') ? '.' + imgPath : imgPath);
              try { if (fs.existsSync(local2)) buf2 = fs.readFileSync(local2); } catch (e) { console.warn('Read local image failed', e && e.message ? e.message : e); }
            }
            if (!buf2) continue;
            // If starting a new row, ensure space on page
            if (col === 0) {
              if (y + imgDisplayHeight + 20 > 780) {
                doc.addPage();
                y = 50;
              }
            }
            const imgX = marginLeft + col * (imgDisplayWidth + spacing);
            try {
              doc.image(buf2, imgX, y, { width: imgDisplayWidth, height: imgDisplayHeight });
              drawnAny = true;
            } catch (e) { console.warn('Draw grid image failed', e && e.message ? e.message : e); }
            col++;
            if (col >= perRow) {
              col = 0;
              y += imgDisplayHeight + 12;
            }
          }
          if (col !== 0) {
            // finished a partial row
            y += imgDisplayHeight + 12;
          } else if (!drawnAny) {
            // nothing drawn -> no change
          }
        }
      } catch (e) {
        console.warn('Error drawing images for service', s.id_servicio, e && e.message ? e.message : e);
      }
    }

    // Separator and totals aligned to right
    doc.moveTo(360, y + 4).lineTo(545, y + 4).strokeColor('#dddddd').stroke();
    doc.font('Helvetica-Bold').fontSize(12).fillColor('#000').text('Total:', 360, y + 12);
    doc.font('Helvetica-Bold').fontSize(16).fillColor('#000').text(`$ ${grandTotal.toFixed(2)}`, 450, y + 8);

    // Footer
    const range = doc.bufferedPageRange();
    for (let i = 0; i < range.count; i++) {
      doc.switchToPage(i);
      doc.font('Helvetica').fontSize(8).fillColor('#777').text('Taller de Motos Moreira Racing - Gracias por confiar en nosotros', 50, 780, { align: 'center', width: 495 });
      doc.fontSize(8).text(`Página ${i + 1} de ${range.count}`, 50, 792, { align: 'center', width: 495 });
    }

    doc.end();

    writeStream.on('finish', async () => {
      try {
        // insert a factura row per service (schema requires id_servicio not null)
        for (const s of services) {
          await execute('INSERT INTO facturas (id_servicio, fecha, total, pdf_path) VALUES (?, ?, ?, ?)', [s.id_servicio, fechaHoy, s.costo, filepath]);
        }
        res.download(filepath, filename, (err) => { if (err) console.error('Error sending file', err && err.stack ? err.stack : err); });
      } catch (ie) {
        console.error('Error saving factura records', ie && ie.stack ? ie.stack : ie);
        res.status(500).json({ error: 'error saving factura records', detail: ie && ie.message ? ie.message : String(ie) });
      }
    });

    writeStream.on('error', (err) => {
      console.error('Error writing PDF', err && err.stack ? err.stack : err);
      res.status(500).json({ error: 'error generating pdf', detail: err && err.message ? err.message : String(err) });
    });

  } catch (err) {
    console.error('Unhandled error in /invoices', err && err.stack ? err.stack : err);
    res.status(500).json({ error: 'error generating invoice', detail: err && err.message ? err.message : String(err) });
  }
});

// Health
app.get('/health', (req, res) => res.json({ status: 'ok' }));

// DB connectivity check (diagnostic endpoint)
app.get('/db-check', async (req, res) => {
  try {
    const rows = await query('SELECT 1 AS ok');
    res.json({ ok: true, rows });
  } catch (e) {
    console.error('DB check failed:', e && e.stack ? e.stack : e);
    res.status(500).json({ ok: false, error: e.message || String(e), stack: e.stack });
  }
});

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
