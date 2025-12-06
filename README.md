# Backend - Taller de Motos Moreira

Pequeño backend en Node.js/Express para gestionar clientes, motos, servicios y generar facturas en PDF.

Requisitos:
- Node.js 18+ (o compatible)
- MySQL (o MariaDB)

Pasos rápidos:

1. Copia `.env.example` a `.env` y ajusta las credenciales de la base de datos.

2. Inicializa la base de datos (desde MySQL Workbench o terminal) ejecutando `backend/sql/init.sql`.

	Alternativamente puedes usar el script incluido que ejecuta `sql/init.sql` usando las credenciales de tu `.env`:

```powershell
cd backend
npm install
# Copia .env.example -> .env y ajusta las credenciales DB
npm run init-db
```

3. Instala dependencias y arranca el servidor:

```powershell
cd backend
npm install
npm run dev
```

Documentación API
-----------------

Después de arrancar el servidor puedes ver la documentación OpenAPI en:

```
http://localhost:3000/docs
```

Esto muestra una UI interactiva con los endpoints disponibles.

4. Coloca tu logo en `backend/assets/logo.png`. Si no existe, las facturas se generan sin logo.

Logo para facturas
-----------------

Coloca tu archivo de logo en `backend/assets/logo.png`. El backend usa `LOGO_PATH` de `.env` si quieres una ruta distinta.

Ejemplo:

```powershell
# coloca logo en backend/assets/logo.png
# o ajusta .env:
LOGO_PATH=./assets/mi_logo.png
```

Endpoints principales (JSON):
- `POST /clients` { nombre, telefono, direccion }
- `GET /clients`
- `POST /motos` { id_cliente, marca, modelo, anio, placa }
- `GET /motos`
- `POST /services` { id_moto, descripcion, fecha (YYYY-MM-DD), costo }
- `GET /services`
- `POST /invoices` { id_servicio } -> genera PDF y lo descarga

Ejemplo: crear cliente y moto (curl):

```powershell
curl -X POST http://localhost:3000/clients -H "Content-Type: application/json" -d '{"nombre":"Juan Perez","telefono":"123456789","direccion":"Calle Falsa 123"}'
```

Generar factura (descarga):

```powershell
curl -X POST http://localhost:3000/invoices -H "Content-Type: application/json" -d '{"id_servicio":1}' --output factura.pdf
```
