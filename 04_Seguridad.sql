USE ecommerce_db;

CREATE ROLE IF NOT EXISTS 'Administrador_Sistema';
CREATE ROLE IF NOT EXISTS 'Gerente_Marketing';
CREATE ROLE IF NOT EXISTS 'Analista_Datos';
CREATE ROLE IF NOT EXISTS 'Empleado_Inventario';
CREATE ROLE IF NOT EXISTS 'Atencion_Cliente';
CREATE ROLE IF NOT EXISTS 'Auditor_Financiero';
CREATE ROLE IF NOT EXISTS 'Visitante';

GRANT ALL PRIVILEGES ON ecommerce_db.* TO 'Administrador_Sistema';

GRANT SELECT ON ecommerce_db.productos TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.categorias TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.proveedores TO 'Analista_Datos';
GRANT SELECT (id_cliente, nombre, apellido, email, direccion_envio, ciudad,
              fecha_nacimiento, total_gastado, fecha_ultima_compra,
              fecha_registro, activo)
    ON ecommerce_db.clientes TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.vistas_producto TO 'Analista_Datos';

GRANT SELECT, UPDATE (stock, ubicacion) ON ecommerce_db.productos TO 'Empleado_Inventario';

GRANT SELECT ON ecommerce_db.productos TO 'Auditor_Financiero';
GRANT SELECT ON ecommerce_db.log_cambios_precio TO 'Auditor_Financiero';

GRANT SELECT ON ecommerce_db.productos TO 'Visitante';

-- Instala el componente de validación en MySQL 8.0 antes de aplicar la política.
INSTALL COMPONENT 'file://component_validate_password';
SET GLOBAL validate_password.policy = STRONG;
SET GLOBAL validate_password.length = 12;

CREATE USER IF NOT EXISTS 'admin_user'@'localhost' IDENTIFIED BY RANDOM PASSWORD;
CREATE USER IF NOT EXISTS 'marketing_user'@'localhost' IDENTIFIED BY RANDOM PASSWORD;
CREATE USER IF NOT EXISTS 'analyst_user'@'localhost' IDENTIFIED BY RANDOM PASSWORD;
CREATE USER IF NOT EXISTS 'inventory_user'@'localhost' IDENTIFIED BY RANDOM PASSWORD;
CREATE USER IF NOT EXISTS 'support_user'@'localhost' IDENTIFIED BY RANDOM PASSWORD;

GRANT 'Administrador_Sistema' TO 'admin_user'@'localhost';
GRANT 'Gerente_Marketing' TO 'marketing_user'@'localhost';
GRANT 'Analista_Datos' TO 'analyst_user'@'localhost';
GRANT 'Empleado_Inventario' TO 'inventory_user'@'localhost';
GRANT 'Atencion_Cliente' TO 'support_user'@'localhost';

SET DEFAULT ROLE ALL TO 
    'admin_user'@'localhost', 
    'marketing_user'@'localhost', 
    'analyst_user'@'localhost',
    'inventory_user'@'localhost', 
    'support_user'@'localhost';

CREATE OR REPLACE VIEW v_info_clientes_basica AS
SELECT id_cliente, nombre, apellido, email, direccion_envio, fecha_registro
FROM clientes;

GRANT SELECT ON ecommerce_db.v_info_clientes_basica TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.v_info_clientes_basica TO 'Gerente_Marketing';

DROP TEMPORARY TABLE IF EXISTS tmp_remote_root_hosts;
CREATE TEMPORARY TABLE tmp_remote_root_hosts (
    Host VARCHAR(255) PRIMARY KEY
);

INSERT INTO tmp_remote_root_hosts (Host)
SELECT Host
FROM mysql.user
WHERE User = 'root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_restrict_remote_root_accounts$$
CREATE PROCEDURE sp_restrict_remote_root_accounts()
BEGIN
    DECLARE v_done BOOLEAN DEFAULT FALSE;
    DECLARE v_host VARCHAR(255);
    DECLARE remote_root_hosts CURSOR FOR
        SELECT Host FROM tmp_remote_root_hosts;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    OPEN remote_root_hosts;
    root_host_loop: LOOP
        FETCH remote_root_hosts INTO v_host;
        IF v_done THEN
            LEAVE root_host_loop;
        END IF;

        SET @drop_remote_root_sql = CONCAT('DROP USER IF EXISTS ', QUOTE('root'), '@', QUOTE(v_host));
        PREPARE drop_remote_root FROM @drop_remote_root_sql;
        EXECUTE drop_remote_root;
        DEALLOCATE PREPARE drop_remote_root;
    END LOOP;
    CLOSE remote_root_hosts;
END$$

CALL sp_restrict_remote_root_accounts()$$
DROP PROCEDURE sp_restrict_remote_root_accounts$$

DELIMITER ;

DROP TEMPORARY TABLE tmp_remote_root_hosts;

ALTER USER 'analyst_user'@'localhost' WITH MAX_QUERIES_PER_HOUR 500;

CREATE TABLE IF NOT EXISTS usuarios_sucursal (
    usuario     VARCHAR(100) NOT NULL PRIMARY KEY,
    id_sucursal INT NOT NULL DEFAULT 1
);

INSERT INTO usuarios_sucursal (usuario, id_sucursal) VALUES
    ('marketing_user', 1),
    ('analyst_user', 1),
    ('support_user', 1)
ON DUPLICATE KEY UPDATE id_sucursal = VALUES(id_sucursal);

CREATE OR REPLACE
    ALGORITHM = MERGE
    SQL SECURITY DEFINER
VIEW v_ventas_sucursal AS
SELECT v.*
FROM ventas v
INNER JOIN usuarios_sucursal us
    ON us.id_sucursal = v.id_sucursal
WHERE us.usuario = SUBSTRING_INDEX(USER(), '@', 1);

GRANT SELECT ON ecommerce_db.v_ventas_sucursal TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.v_ventas_sucursal TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.v_ventas_sucursal TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.v_ventas_sucursal TO 'Auditor_Financiero';

CREATE OR REPLACE
    ALGORITHM = MERGE
    SQL SECURITY DEFINER
VIEW v_detalle_ventas_sucursal AS
SELECT dv.*
FROM detalle_ventas dv
INNER JOIN ventas v ON v.id_venta = dv.id_venta
INNER JOIN usuarios_sucursal us ON us.id_sucursal = v.id_sucursal
WHERE us.usuario = SUBSTRING_INDEX(USER(), '@', 1);

GRANT SELECT ON ecommerce_db.v_detalle_ventas_sucursal TO 'Gerente_Marketing';
GRANT SELECT ON ecommerce_db.v_detalle_ventas_sucursal TO 'Analista_Datos';
GRANT SELECT ON ecommerce_db.v_detalle_ventas_sucursal TO 'Atencion_Cliente';
GRANT SELECT ON ecommerce_db.v_detalle_ventas_sucursal TO 'Auditor_Financiero';

-- Esta tabla requiere integración con el plugin de auditoría del servidor:
-- MySQL no expone los intentos de autenticación fallidos como eventos SQL.
CREATE TABLE IF NOT EXISTS auditoria_logins_fallidos (
    id_log INT AUTO_INCREMENT PRIMARY KEY,
    usuario VARCHAR(100),
    host_origen VARCHAR(100),
    fecha_intento TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    motivo VARCHAR(255) DEFAULT 'Autenticación fallida'
);

FLUSH PRIVILEGES;