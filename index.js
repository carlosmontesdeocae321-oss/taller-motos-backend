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
    // handle image updates: allow client to provide new image (multipart) or set image_path explicitly
    let imagePath = null;
    // if client sent an explicit image_path (after removing some images), honor it
    if (req.body.image_path) {
      imagePath = req.body.image_path;
    }

    // If a file was uploaded, process it: upload to cloudinary if configured, else store local path
    if (req.file) {
      try {
        if (cloudinaryEnabled && req.file && req.file.path) {
          const uploadRes = await cloudinaryHelper.uploadLocalFile(req.file.path, { folder: 'taller-motos/services' });
          if (uploadRes && uploadRes.secure_url) {
            const newUrl = uploadRes.secure_url;
            // append to existing imagePath if present, otherwise set to newUrl
            if (imagePath && imagePath.length > 0) imagePath = imagePath + ',' + newUrl;
            else {
              // fetch existing path to append
              try {
                const rows = await query('SELECT image_path FROM servicios WHERE id_servicio = ?', [id]);
                const existing = (rows && rows[0] && rows[0].image_path) ? rows[0].image_path : null;
                imagePath = existing ? existing + ',' + newUrl : newUrl;
              } catch (ee) {
                imagePath = newUrl;
              }
            }
          }
          try { fs.unlinkSync(req.file.path); } catch (er) {}
        } else {
          const localPath = `/uploads/services/${req.file.filename}`;
          if (imagePath && imagePath.length > 0) imagePath = imagePath + ',' + localPath;
          else {
            try {
              const rows = await query('SELECT image_path FROM servicios WHERE id_servicio = ?', [id]);
              const existing = (rows && rows[0] && rows[0].image_path) ? rows[0].image_path : null;
              imagePath = existing ? existing + ',' + localPath : localPath;
            } catch (ee) {
              imagePath = localPath;
            }
          }
        }
      } catch (e) {
        console.warn('Error processing uploaded file for update:', e.message);
      }
    }

    // Build update query. If imagePath is null, don't update image_path column.
    if (imagePath !== null) {
      const result = await execute('UPDATE servicios SET id_moto = ?, descripcion = ?, fecha = ?, costo = ?, completed = COALESCE(?, completed), image_path = ? WHERE id_servicio = ?', [id_moto, descripcion, fecha, costo, completed, imagePath, id]);
      res.json({ affectedRows: result.affectedRows });
    } else {
      const result = await execute('UPDATE servicios SET id_moto = ?, descripcion = ?, fecha = ?, costo = ?, completed = COALESCE(?, completed) WHERE id_servicio = ?', [id_moto, descripcion, fecha, costo, completed, id]);
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

    // helper: fetch remote image into a buffer
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

    // generate single PDF that contains all services (professional layout)
    const invoiceId = Date.now();
    const filename = `factura_${invoiceId}.pdf`;
    const filepath = path.join(INVOICES_DIR, filename);

    const doc = new PDFDocument({ size: 'A4', margin: 50, bufferPages: true });
    const writeStream = fs.createWriteStream(filepath);
    doc.pipe(writeStream);

    const fechaHoy = new Date().toISOString().slice(0,10);

    // Header: logo left, title and meta right
    if (fs.existsSync(LOGO_PATH)) {
      try { doc.image(LOGO_PATH, 50, 50, { width: 100 }); } catch (e) { console.warn('Logo draw failed:', e.message); }
    }
    doc.fontSize(20).text('Taller de Motos Moreira Racing', 180, 55);
    doc.fontSize(10).text(`Factura: ${invoiceId}`, 180, 80);
    doc.fontSize(10).text(`Fecha: ${formatDateSpanish(fechaHoy)}`, 180, 95);

    // small divider
    doc.moveTo(50, 120).lineTo(545, 120).strokeColor('#dddddd').stroke();

    // client and moto boxes
    const first = services[0];
    doc.rect(50, 130, 300, 80).stroke('#cccccc');
    doc.fontSize(11).text('Cliente', 58, 136);
    doc.fontSize(10).text(`${first.cliente_nombre || '-'}`, 58, 152);
    doc.fontSize(9).text(`Tel: ${first.telefono || '-'}`, 58, 168);
    doc.fontSize(9).text(`Dir: ${first.direccion || '-'}`, 58, 182);

    doc.rect(370, 130, 225, 80).stroke('#cccccc');
    doc.fontSize(11).text('Moto', 378, 136);
    doc.fontSize(10).text(`${first.marca || '-'} ${first.modelo || '-'}`, 378, 152);
    doc.fontSize(9).text(`Placa: ${first.placa || '-'}`, 378, 168);

    // Services list with optional thumbnail at right
    let y = 220;
    doc.fontSize(12).text('Detalle de servicios', 50, y - 14);
    let grandTotal = 0.0;

    for (let idx = 0; idx < services.length; idx++) {
      const s = services[idx];
      const costo = Number(s.costo || 0);
      grandTotal += costo;

      const dateOnly = (s.fecha || '').toString().split('T')[0].split(' ')[0].substring(0,10);
      const displayDate = formatDateSpanish(dateOnly);

      // description block
      doc.fontSize(10).fillColor('#000').text(`${idx+1}. ${s.descripcion || '-'}`, 50, y, { width: 360 });
      doc.fontSize(9).fillColor('#555').text(`Fecha: ${displayDate}`, 420, y);
      doc.fontSize(10).fillColor('#000').text(`Precio: $ ${costo.toFixed(2)}`, 420, y + 14);

      // thumbnail handling
      if (s.image_path) {
        try {
          const imgs = ('' + s.image_path).split(',').map(p => p.trim()).filter(Boolean);
          const firstImg = imgs[0];
          if (firstImg) {
            let buf = null;
            if (firstImg.startsWith('http://') || firstImg.startsWith('https://')) {
              try { buf = await fetchImageBuffer(firstImg); } catch (e) { console.warn('Fetch img failed', e.message); }
            } else {
              const local = path.join(__dirname, firstImg.startsWith('/') ? '.' + firstImg : firstImg);
              try { if (fs.existsSync(local)) buf = fs.readFileSync(local); } catch (e) { console.warn('Read local img failed', e.message); }
            }
            if (buf) {
              try { doc.image(buf, 480, y - 2, { width: 80, height: 60, align: 'right' }); } catch (e) { console.warn('Draw thumb failed', e.message); }
            }
          }
        } catch (ie) { console.warn('Image processing error for service', s.id_servicio, ie.message || ie); }
      }

      y += 76; // leave space for thumbnail
      if (y > 720) { doc.addPage(); y = 50; }
    }

    // Totals box
    doc.rect(360, y, 185, 60).stroke('#cccccc');
    doc.fontSize(12).text('Total', 370, y + 10);
    doc.fontSize(18).text(`$ ${grandTotal.toFixed(2)}`, 430, y + 8);

    // Footer and page numbers
    const range = doc.bufferedPageRange();
    for (let i = 0; i < range.count; i++) {
      doc.switchToPage(i);
      doc.fontSize(8).fillColor('#777').text('Taller de Motos Moreira Racing - Gracias por confiar en nosotros', 50, 780, { align: 'center', width: 495 });
      doc.fontSize(8).text(`Página ${i + 1} de ${range.count}`, 50, 792, { align: 'center', width: 495 });
    }

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
