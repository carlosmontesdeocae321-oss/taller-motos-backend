Despliegue del backend "Taller de Motos"

Opciones soportadas aquí:
- Docker (con push a Docker Hub / cualquier registry)
- Heroku (Procfile)

Requisitos previos
- Tener una base de datos MySQL disponible y accesible desde el servidor en la nube (RDS, ClearDB, Cloud SQL, Azure Database, etc.).
- Configurar variables de entorno (ver sección "Variables de entorno").
- Node 18+ para pruebas locales si no usas Docker.

Variables de entorno importantes
- `DB_HOST` — host o IP de la base de datos
- `DB_USER` — usuario MySQL
- `DB_PASSWORD` — contraseña MySQL
- `DB_NAME` — nombre de la base de datos (ej. `taller`)
- `PORT` — puerto del servidor (por defecto `3000`)
- `BASE_URL` — (opcional) URL base pública si necesitas construir rutas absolutas en PDFs o emails

Inicializar la base de datos
- El repositorio contiene `sql/init.sql` y un script `scripts/init-db.js` que pueden ejecutar contra la DB remota.
- Para ejecutarlo desde el servidor (con las variables de entorno apuntando al DB remoto):

```powershell
cd C:\backend
# instalar dependencias si no las tienes
npm ci
# ejecutar script de inicialización
node scripts/init-db.js
```

Despliegue con Docker (local / cloud)
1) Construir la imagen localmente:

```powershell
cd C:\backend
docker build -t tu-usuario/taller-motos-backend:latest .
```

2) Probar localmente (pasando variables de entorno; apunta a una DB accesible):

```powershell
docker run --rm -p 3000:3000 `
  -e DB_HOST=<db-host> `
  -e DB_USER=<db-user> `
  -e DB_PASSWORD=<db-password> `
  -e DB_NAME=<db-name> `
  tu-usuario/taller-motos-backend:latest
```

3) Subir imagen a Docker Hub (o cualquier registry):

```powershell
docker login
docker push tu-usuario/taller-motos-backend:latest
```

4) Crear instancia en el proveedor cloud (Azure App Service, AWS ECS, Google Cloud Run, DigitalOcean App Platform, etc.) y configurar la imagen y variables de entorno.

Notas sobre archivos subidos
- Actualmente las fotos se almacenan en disco (`uploads/services`). Para desplegar en producción te recomiendo usar almacenamiento persistente o externo (S3 / Azure Blob / Cloud Storage):
  - Opción 1: montar un volumen persistente en el servicio (si tu proveedor lo soporta).
  - Opción 2: modificar el backend para subir imágenes a S3/Blob y almacenar la URL en la DB (recomendado para escalado horizontal).

Despliegue en Heroku (rápido)
1) Crear app en Heroku y añadir addon MySQL o configurar un host MySQL externo.
2) Subir el repo y configurar variables de entorno:

```powershell
heroku login
heroku create nombre-app
# establecer variables
heroku config:set DB_HOST=<host> DB_USER=<user> DB_PASSWORD=<pass> DB_NAME=<db>
# subir (si el remote es heroku)
git push heroku main
```

Alternativa: usar contenedores en Heroku:

```powershell
# build and push container to heroku
heroku container:login
heroku container:push web -a nombre-app
heroku container:release web -a nombre-app
```

Verificación y pruebas
- Después de desplegar, comprobar `GET /features` para ver si `uploadEnabled` es true.
- Crear un cliente/moto y crear un servicio con imagen desde la app Flutter apuntando al `BASE_URL` del backend.
- Generar una factura (POST `/invoices`) y descargar el PDF.

Consejos de seguridad
- No subir `.env` ni credenciales al repo.
- Usar secretos del proveedor para las variables de entorno.
- Habilitar HTTPS en el endpoint público.

¿Quieres que:
- 1) prepare un `docker-compose.yml` para probar localmente con un MySQL container? (útil para pruebas completas)
- 2) o genero la configuración para desplegar directamente en Azure Web App / AWS ECS con pasos concretos?

Dime qué proveedor prefieres y preparo los pasos/artefactos.
