
CREATE DATABASE IF NOT EXISTS ecommerce_db
    CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE ecommerce_db;

CREATE TABLE categorias (
    id_categoria    INT AUTO_INCREMENT PRIMARY KEY,
    nombre          VARCHAR(100)    NOT NULL UNIQUE,
    descripcion     TEXT            NULL,
    id_categoria_padre INT          NULL,

    CONSTRAINT fk_categoria_padre
        FOREIGN KEY (id_categoria_padre) REFERENCES categorias(id_categoria)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE = InnoDB;

CREATE TABLE proveedores (
    id_proveedor       INT AUTO_INCREMENT PRIMARY KEY,
    nombre             VARCHAR(150)    NOT NULL,
    email_contacto     VARCHAR(150)    NULL UNIQUE,
    telefono_contacto  VARCHAR(30)     NULL
) ENGINE = InnoDB;

CREATE TABLE productos (
    id_producto             INT AUTO_INCREMENT PRIMARY KEY,
    nombre                  VARCHAR(150)    NOT NULL UNIQUE,
    descripcion             TEXT            NULL,
    precio                  DECIMAL(10,2)   NOT NULL,
    costo                   DECIMAL(10,2)   NOT NULL DEFAULT 0,
    stock                   INT             NOT NULL DEFAULT 0,
    ubicacion               VARCHAR(100)    NULL,
    umbral_minimo_stock     INT             NOT NULL DEFAULT 5,
    sku                     VARCHAR(50)     NOT NULL UNIQUE,
    id_categoria            INT             NOT NULL,
    id_proveedor            INT             NOT NULL,
    fecha_creacion          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                                             ON UPDATE CURRENT_TIMESTAMP,
    activo                  BOOLEAN         NOT NULL DEFAULT TRUE,

    CONSTRAINT chk_precio_positivo   CHECK (precio > 0),
    CONSTRAINT chk_costo_no_negativo CHECK (costo >= 0),
    CONSTRAINT chk_stock_no_negativo CHECK (stock >= 0),

    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria)
        ON UPDATE CASCADE ON DELETE RESTRICT,

    CONSTRAINT fk_producto_proveedor
        FOREIGN KEY (id_proveedor) REFERENCES proveedores(id_proveedor)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

CREATE INDEX idx_productos_categoria ON productos(id_categoria);
CREATE INDEX idx_productos_proveedor ON productos(id_proveedor);

CREATE TABLE clientes (
    id_cliente          INT AUTO_INCREMENT PRIMARY KEY,
    nombre              VARCHAR(100)    NOT NULL,
    apellido            VARCHAR(100)    NOT NULL,
    email               VARCHAR(150)    NOT NULL UNIQUE,
    contrasena_hash     VARCHAR(255)    NOT NULL,
    direccion_envio     VARCHAR(255)    NULL,
    ciudad              VARCHAR(100)    NULL,
    fecha_nacimiento    DATE            NULL,
    total_gastado       DECIMAL(12,2)   NOT NULL DEFAULT 0,
    fecha_ultima_compra DATETIME        NULL,
    fecha_registro      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    activo              BOOLEAN         NOT NULL DEFAULT TRUE
) ENGINE = InnoDB;

CREATE TABLE ventas (
    id_venta        INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente      INT             NOT NULL,
    id_sucursal     INT             NOT NULL DEFAULT 1,
    fecha_venta     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado          ENUM('Pendiente de Pago','Procesando','Enviado',
                         'Entregado','Cancelado')
                                    NOT NULL DEFAULT 'Pendiente de Pago',
    total           DECIMAL(12,2)   NOT NULL DEFAULT 0,

    CONSTRAINT fk_venta_cliente
        FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

CREATE INDEX idx_ventas_cliente ON ventas(id_cliente);
CREATE INDEX idx_ventas_fecha ON ventas(fecha_venta);

CREATE TABLE detalle_ventas (
    id_detalle                 INT AUTO_INCREMENT PRIMARY KEY,
    id_venta                   INT             NOT NULL,
    id_producto                INT             NOT NULL,
    cantidad                   INT             NOT NULL,
    precio_unitario_congelado  DECIMAL(10,2)   NOT NULL,

    CONSTRAINT chk_cantidad_positiva CHECK (cantidad > 0),

    CONSTRAINT fk_detalle_venta
        FOREIGN KEY (id_venta) REFERENCES ventas(id_venta)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT fk_detalle_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE = InnoDB;

CREATE INDEX idx_detalle_venta ON detalle_ventas(id_venta);
CREATE INDEX idx_detalle_producto ON detalle_ventas(id_producto);

CREATE TABLE vistas_producto (
    id_vista     BIGINT AUTO_INCREMENT PRIMARY KEY,
    id_producto  INT NOT NULL,
    id_cliente   INT NULL,
    fecha_vista  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_vista_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON UPDATE CASCADE ON DELETE CASCADE,

    CONSTRAINT fk_vista_cliente
        FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE = InnoDB;

CREATE INDEX idx_vistas_producto_fecha ON vistas_producto(id_producto, fecha_vista);

CREATE TABLE log_cambios_precio (
    id_log          INT AUTO_INCREMENT PRIMARY KEY,
    id_producto     INT             NOT NULL,
    precio_anterior DECIMAL(10,2)   NOT NULL,
    precio_nuevo    DECIMAL(10,2)   NOT NULL,
    fecha_cambio    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_log_producto
        FOREIGN KEY (id_producto) REFERENCES productos(id_producto)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE = InnoDB;

INSERT INTO categorias (nombre, descripcion) VALUES
('Electrónica',      'Dispositivos electrónicos, gadgets y accesorios tecnológicos'),
('Ropa',              'Prendas de vestir para hombre, mujer y niños'),
('Hogar',             'Artículos para el hogar y decoración'),
('Deportes',          'Equipamiento y ropa deportiva'),
('Libros',            'Libros físicos de diversos géneros');

INSERT INTO proveedores (nombre, email_contacto, telefono_contacto) VALUES
('TechGlobal S.A.S.',        'ventas@techglobal.com',   '3101234567'),
('Moda Express Ltda.',       'contacto@modaexpress.com','3117654321'),
('HogarPlus Distribuciones', 'info@hogarplus.com',      '3123456789'),
('DeporMax S.A.',            'pedidos@depormax.com',    '3134567890'),
('Editorial Andina',         'ventas@editorialandina.com','3145678901');

INSERT INTO productos
    (nombre, descripcion, precio, costo, stock, umbral_minimo_stock, sku, id_categoria, id_proveedor, activo)
VALUES
('Audífonos Bluetooth X200',    'Audífonos inalámbricos con cancelación de ruido', 189900, 110000, 45, 10, 'SKU-ELEC-001', 1, 1, TRUE),
('Smartwatch FitPro',           'Reloj inteligente con monitor de ritmo cardíaco',  349900, 210000, 30, 8,  'SKU-ELEC-002', 1, 1, TRUE),
('Cargador USB-C 65W',          'Cargador rápido compatible con laptops y móviles',  79900,  35000, 80, 15, 'SKU-ELEC-003', 1, 1, TRUE),
('Teclado Mecánico RGB',        'Teclado gamer con switches azules',                219900, 120000, 25, 5,  'SKU-ELEC-004', 1, 1, TRUE),
('Mouse Inalámbrico Pro',       'Mouse ergonómico de alta precisión',                89900,  40000, 60, 10, 'SKU-ELEC-005', 1, 1, TRUE),
('Camiseta Básica Algodón',     'Camiseta unisex 100% algodón',                      39900,  15000, 150,20, 'SKU-ROPA-001', 2, 2, TRUE),
('Jean Slim Fit',               'Jean de mezclilla corte slim',                      129900,  55000, 70, 10, 'SKU-ROPA-002', 2, 2, TRUE),
('Chaqueta Impermeable',        'Chaqueta resistente al agua para clima frío',       249900, 130000, 20, 5,  'SKU-ROPA-003', 2, 2, TRUE),
('Sudadera con Capucha',        'Sudadera unisex de algodón perchado',               99900,  42000, 55, 10, 'SKU-ROPA-004', 2, 2, TRUE),
('Set de Sábanas Queen',        'Juego de sábanas 100% algodón tamaño Queen',        119900,  50000, 40, 8,  'SKU-HOGAR-001', 3, 3, TRUE),
('Lámpara de Mesa LED',         'Lámpara regulable con luz cálida y fría',            69900,  28000, 35, 6,  'SKU-HOGAR-002', 3, 3, TRUE),
('Set de Ollas Antiadherentes', 'Juego de 5 ollas con recubrimiento antiadherente',  349900, 180000, 15, 5,  'SKU-HOGAR-003', 3, 3, TRUE),
('Balón de Fútbol Pro',         'Balón oficial de competencia talla 5',               89900,  40000, 50, 10, 'SKU-DEP-001',   4, 4, TRUE),
('Mancuernas Ajustables 20kg',  'Par de mancuernas ajustables para entrenamiento',   279900, 150000, 18, 4,  'SKU-DEP-002',   4, 4, TRUE),
('Colchoneta de Yoga',          'Colchoneta antideslizante para yoga y pilates',      59900,  22000, 65, 12, 'SKU-DEP-003',   4, 4, TRUE),
('Novela: El Camino Perdido',   'Novela de ficción contemporánea',                    54900,  20000, 40, 8,  'SKU-LIB-001',   5, 5, TRUE),
('Guía de Programación SQL',    'Libro técnico introductorio a bases de datos',       74900,  28000, 30, 6,  'SKU-LIB-002',   5, 5, TRUE),
('Cuento Infantil Ilustrado',   'Libro infantil con ilustraciones a color',           34900,  12000, 60, 10, 'SKU-LIB-003',   5, 5, TRUE),
('Audífonos Gamer Surround',    'Audífonos con sonido envolvente 7.1',               159900,  85000, 3,  10, 'SKU-ELEC-006', 1, 1, TRUE),
('Termo Acero Inoxidable',      'Termo de 1L mantiene temperatura por 12 horas',      44900,  18000, 2,  10, 'SKU-HOGAR-004', 3, 3, TRUE);

INSERT INTO clientes
    (nombre, apellido, email, contrasena_hash, direccion_envio, ciudad, fecha_nacimiento, fecha_registro)
VALUES
('Laura',    'Martínez',  'laura.martinez@email.com',   '$2y$10$hashDemo01', 'Cra 15 #45-20', 'Bogotá',      '1995-03-12', '2025-10-05 09:15:00'),
('Andrés',   'Gómez',     'andres.gomez@email.com',     '$2y$10$hashDemo02', 'Calle 80 #12-34','Medellín',    '1990-07-25', '2025-11-02 14:30:00'),
('Camila',   'Rodríguez', 'camila.rodriguez@email.com', '$2y$10$hashDemo03', 'Av. Siempre Viva #10','Cali',  '1998-01-30', '2026-01-10 10:05:00'),
('Julián',   'Pérez',     'julian.perez@email.com',     '$2y$10$hashDemo04', 'Cra 7 #23-11',  'Bogotá',      '1988-11-05', '2026-02-14 16:45:00'),
('Valentina','López',     'valentina.lopez@email.com',  '$2y$10$hashDemo05', 'Calle 5 #67-89','Barranquilla','2000-06-18', '2026-03-01 08:20:00'),
('Sebastián','Torres',    'sebastian.torres@email.com', '$2y$10$hashDemo06', 'Diagonal 34 #8-90','Cúcuta',   '1993-09-22', '2026-04-18 11:00:00'),
('Mariana',  'Castro',    'mariana.castro@email.com',   '$2y$10$hashDemo07', 'Cra 20 #50-15', 'Bucaramanga', '1997-02-14', '2026-05-22 13:10:00'),
('Diego',    'Ramírez',   'diego.ramirez@email.com',    '$2y$10$hashDemo08', 'Calle 100 #15-40','Bogotá',    '1985-12-01', '2026-06-09 09:50:00'),
('Isabella', 'Hernández', 'isabella.hernandez@email.com','$2y$10$hashDemo09','Cra 45 #12-60', 'Medellín',    '2001-04-09', '2026-07-15 17:25:00'),
('Nicolás',  'Vargas',    'nicolas.vargas@email.com',   '$2y$10$hashDemo10', 'Calle 30 #22-18','Cali',       '1992-08-27', '2026-08-20 12:40:00');

INSERT INTO ventas (id_cliente, fecha_venta, estado, total) VALUES
(1, '2025-11-10 10:30:00', 'Entregado',  269800),
(2, '2025-11-20 15:00:00', 'Entregado',  349900),
(1, '2025-12-05 09:45:00', 'Entregado',  119900),
(3, '2026-01-15 11:20:00', 'Entregado',  174700),
(4, '2026-02-10 14:10:00', 'Entregado',  349900),
(2, '2026-02-18 16:30:00', 'Cancelado',   89900),
(5, '2026-03-05 10:00:00', 'Entregado',  259700),
(1, '2026-03-22 12:15:00', 'Entregado',   79900),
(6, '2026-04-01 09:30:00', 'Entregado',  279900),
(3, '2026-04-19 17:00:00', 'Entregado',  144800),
(7, '2026-05-08 13:45:00', 'Entregado',  219900),
(4, '2026-05-25 11:10:00', 'Enviado',    349900),
(8, '2026-06-02 10:20:00', 'Entregado',  109800),
(2, '2026-06-14 15:40:00', 'Entregado',  189900),
(9, '2026-07-03 09:00:00', 'Entregado',  354800),
(5, '2026-07-21 14:50:00', 'Entregado',   99900),
(10,'2026-08-05 11:30:00', 'Entregado',  129900),
(6, '2026-08-17 16:20:00', 'Procesando', 249900),
(1, '2026-09-02 10:10:00', 'Entregado',  159900),
(3, '2026-09-15 13:25:00', 'Pendiente de Pago', 89900);

INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
(1, 1, 1, 189900), (1, 3, 1, 79900),
(2, 2, 1, 349900),
(3, 10, 1, 119900),
(4, 6, 1, 39900), (4, 16, 1, 54900), (4, 3, 1, 79900),
(5, 2, 1, 349900),
(6, 5, 1, 89900),
(7, 8, 1, 249900), (7, 18, 1, 9800),
(8, 3, 1, 79900),
(9, 14, 1, 279900),
(10, 7, 1, 129900), (10, 18, 1, 14900),
(11, 4, 1, 219900),
(12, 2, 1, 349900),
(13, 9, 1, 99900), (13, 18, 1, 9900),
(14, 1, 1, 189900),
(15, 12, 1, 349900), (15, 18, 1, 4900),
(16, 9, 1, 99900),
(17, 7, 1, 129900),
(18, 8, 1, 249900),
(19, 4, 1, 159900),
(20, 5, 1, 89900);

INSERT INTO vistas_producto (id_producto, id_cliente, fecha_vista) VALUES
(1, 1, '2026-09-01 08:15:00'),
(1, 2, '2026-09-02 10:20:00'),
(1, 3, '2026-09-03 12:30:00'),
(2, 1, '2026-09-04 09:10:00'),
(2, 4, '2026-09-05 11:45:00'),
(3, 2, '2026-09-06 14:00:00'),
(3, 5, '2026-09-07 16:25:00'),
(3, 6, '2026-09-08 13:50:00'),
(4, 3, '2026-09-09 10:05:00'),
(5, 1, '2026-09-10 15:40:00'),
(6, 7, '2026-09-11 09:30:00'),
(8, 8, '2026-09-12 18:10:00'),
(10, 9, '2026-09-13 12:00:00'),
(12, 10, '2026-09-14 16:45:00'),
(14, 2, '2026-09-15 17:15:00');
