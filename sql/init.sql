-- Inicialización de la base de datos para Taller de Motos Moreira
CREATE DATABASE IF NOT EXISTS moreira CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE moreira;

CREATE TABLE IF NOT EXISTS clientes (
  id_cliente INT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(200) NOT NULL,
  telefono VARCHAR(50),
  direccion VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS motos (
  id_moto INT AUTO_INCREMENT PRIMARY KEY,
  id_cliente INT NOT NULL,
  marca VARCHAR(100),
  modelo VARCHAR(100),
  anio YEAR,
  placa VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS servicios (
  id_servicio INT AUTO_INCREMENT PRIMARY KEY,
  id_moto INT NOT NULL,
  descripcion TEXT NOT NULL,
  fecha DATE NOT NULL,
  costo DECIMAL(10,2) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (id_moto) REFERENCES motos(id_moto) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS facturas (
  id_factura INT AUTO_INCREMENT PRIMARY KEY,
  id_servicio INT NOT NULL,
  fecha DATE NOT NULL,
  total DECIMAL(10,2) NOT NULL,
  pdf_path VARCHAR(500),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (id_servicio) REFERENCES servicios(id_servicio) ON DELETE CASCADE
);

-- Índices de ayuda
-- Note: MySQL prior to 8.0 ignores IF NOT EXISTS in CREATE INDEX; adjust if needed
CREATE INDEX idx_clientes_nombre ON clientes(nombre);
CREATE INDEX idx_motos_placa ON motos(placa);

-- Datos de ejemplo (seed)
INSERT INTO clientes (nombre, telefono, direccion) VALUES
  ('Juan Perez', '123456789', 'Calle Falsa 123'),
  ('María Gómez', '987654321', 'Av. Siempre Viva 742');

INSERT INTO motos (id_cliente, marca, modelo, anio, placa) VALUES
  (1, 'Yamaha', 'YZF-R3', 2019, 'ABC123'),
  (2, 'Honda', 'CBR500R', 2020, 'XYZ789');

INSERT INTO servicios (id_moto, descripcion, fecha, costo) VALUES
  (1, 'Cambio de aceite y filtro', '2025-11-20', 150.00),
  (2, 'Revisión general', '2025-11-22', 200.00);
