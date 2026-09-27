USE ecommerce_db;

CREATE ROLE IF NOT EXISTS 'Administrador_Sistema';
CREATE ROLE IF NOT EXISTS 'Gerente_Marketing';
CREATE ROLE IF NOT EXISTS 'Analista_Datos';
CREATE ROLE IF NOT EXISTS 'Empleado_Inventario';
CREATE ROLE IF NOT EXISTS 'Atencion_Cliente';
CREATE ROLE IF NOT EXISTS 'Auditor_Financiero';
CREATE ROLE IF NOT EXISTS 'Visitante';

GRANT ALL PRIVILEGES ON ecommerce_db.* TO 'Administrador_Sistema';

GRANT SELECT ON ecommerce_db.ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.clientes TO 'Gerente_Marketing';

GRANT SELECT ON ecommerce_db.productos TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.categorias TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.proveedores TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.clientes TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.ventas TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Analista_Datos';

GRANT SELECT, UPDATE (stock) ON ecommerce_db.productos TO 'Empleado_Inventario';

GRANT SELECT ON ecommerce_db.ventas TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Atencion_Cliente';

GRANT SELECT ON ecommerce_db.ventas TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.detalle_ventas TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.productos TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.log_cambios_precio TO 'Auditor_Financiero';

GRANT SELECT ON ecommerce_db.productos TO 'Visitante';

CREATE USER IF NOT EXISTS 'admin_user'@'localhost' IDENTIFIED BY 'AdminP@ssw0rd2026!';
CREATE USER IF NOT EXISTS 'marketing_user'@'localhost' IDENTIFIED BY 'MktgP@ssw0rd2026!';
CREATE USER IF NOT EXISTS 'inventory_user'@'localhost' IDENTIFIED BY 'InvP@ssw0rd2026!';
CREATE USER IF NOT EXISTS 'support_user'@'localhost' IDENTIFIED BY 'SuppP@ssw0rd2026!';

GRANT 'Administrador_Sistema' TO 'admin_user'@'localhost';
GRANT 'Gerente_Marketing' TO 'marketing_user'@'localhost';
GRANT 'Empleado_Inventario' TO 'inventory_user'@'localhost';
GRANT 'Atencion_Cliente' TO 'support_user'@'localhost';

SET DEFAULT ROLE ALL TO 
    'admin_user'@'localhost', 
    'marketing_user'@'localhost', 
    'inventory_user'@'localhost', 
    'support_user'@'localhost';

REVOKE DELETE, DROP ON ecommerce_db.* FROM 'Analista_Datos';

GRANT EXECUTE ON PROCEDURE ecommerce_db.sp_GenerarReporteMensualVentas TO 'Gerente_Marketing';

CREATE OR REPLACE VIEW v_info_clientes_basica AS
SELECT id_cliente, nombre, apellido, email, direccion_envio, fecha_registro
FROM clientes;

GRANT SELECT ON ecommerce_db.v_info_clientes_basica TO 'Atencion_Cliente';

REVOKE UPDATE (precio) ON ecommerce_db.productos FROM 'Empleado_Inventario';

SET GLOBAL validate_password.policy = MEDIUM;
SET GLOBAL validate_password.length = 8;

DELETE FROM mysql.user WHERE User = 'root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

ALTER USER 'marketing_user'@'localhost' WITH MAX_QUERIES_PER_HOUR 500;

ALTER TABLE ventas ADD COLUMN IF NOT EXISTS id_sucursal INT DEFAULT 1;

CREATE OR REPLACE VIEW v_ventas_sucursal AS
SELECT * FROM ventas WHERE id_sucursal = 1;

CREATE TABLE IF NOT EXISTS auditoria_logins_fallidos (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    usuario VARCHAR(100),
    host_origen VARCHAR(100),
    fecha_intento TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    motivo VARCHAR(255) DEFAULT 'Autenticación fallida'
);

FLUSH PRIVILEGES;