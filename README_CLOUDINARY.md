Cloudinary integration — Taller de Motos backend

Overview
- This backend can upload service photos to Cloudinary when Cloudinary credentials are provided.
- If Cloudinary is not configured, the server will save uploads under `/uploads/services` and serve them statically, but this is ephemeral and not suitable for production on Render (use Cloudinary for persistence).

Configure Cloudinary
1) Create a free account at https://cloudinary.com/ (they have a free tier sufficient for development).
2) In the Cloudinary dashboard, find your `Cloud name`, `API Key`, and `API Secret`.

Set environment variables (preferred)
- Set either `CLOUDINARY_URL` or the three variables below in your environment / Render dashboard / GitHub Secrets:
  - `CLOUDINARY_CLOUD_NAME`
  - `CLOUDINARY_API_KEY`
  - `CLOUDINARY_API_SECRET`

`CLOUDINARY_URL` format (single env var alternative):
```
cloudinary://<API_KEY>:<API_SECRET>@<CLOUD_NAME>
```

Server-side uploads
- The backend automatically uploads files received in `POST /services` (multipart field named `image`) to Cloudinary if the environment is configured. The `image_path` field stored in the DB will contain the remote `secure_url`.

Client-side uploads (direct to Cloudinary)
- To avoid sending files through the backend, you can upload directly from the client to Cloudinary using a signed upload. The backend exposes `GET /cloudinary-sign` which returns a `signature`, `timestamp`, and `api_key` if Cloudinary is configured. Use those values to make a signed upload from the client. Alternatively, configure an unsigned upload preset in Cloudinary and upload directly using that preset (no server signature needed).

Server-side direct upload endpoint
- The backend now exposes `POST /upload` (multipart form, field name `file`) which will upload the received file to Cloudinary (if configured) and return the Cloudinary response JSON. If Cloudinary is not available, it will return the local path under `/uploads/services`.

Example `curl` for the new endpoint:
```powershell
curl -v -X POST "http://localhost:3000/upload" -F "file=@C:\path\to\photo.jpg"
```

The server enforces a max file size of 5MB and accepts common image types (`jpeg`, `png`, `webp`, `gif`, `svg`).

Testing locally
1) Install dependencies:
```powershell
cd C:\backend
npm ci
```
2) Start server with env vars set (example using PowerShell):
```powershell
$env:CLOUDINARY_CLOUD_NAME = 'your-cloud-name'
$env:CLOUDINARY_API_KEY = '...'
$env:CLOUDINARY_API_SECRET = '...'
node index.js
```
3) Test `POST /services` with `curl` (multipart):
```powershell
curl -v -X POST "http://localhost:3000/services" -F "id_moto=1" -F "descripcion=Prueba" -F "fecha=2025-12-06" -F "costo=100" -F "image=@C:\path\to\photo.jpg"
```
- If Cloudinary is enabled, the response DB `image_path` will contain the Cloudinary `https://...` URL.

Notes
- Files are temporarily stored on disk by `multer` before upload; after successful Cloudinary upload the local temp file is removed.
- If you plan to let users upload large files, consider adding validation (file size, image types) on the server or using direct client uploads.

If you want, I can:
- Update the Flutter app to upload directly to Cloudinary using signed uploads (safer and faster), or
- Add server-side validation for max file size and allowed mime types.
